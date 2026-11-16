//! Sends the installer's privileged commands to an elevated copy of ourselves.
//!
//! The commands used to be written to a `.cmd` file which an elevated `cmd.exe`
//! then ran. Even after moving that file out of `%TEMP%` and renaming it, the
//! pattern - a script on disk whose body creates a service - is the one scanners
//! score highest, and it produced a real `HEUR/Malware.bat.Gen` detection.
//!
//! There is no script now. The parent creates a named pipe, starts
//! `NexDesk.exe --elevated-setup <pipe> <token> <parent_pid>` with the `runas`
//! verb, and writes the command text into that pipe. The elevated copy reads it
//! and executes each command directly (see `installer_exec`). Nothing is staged
//! on disk, and `cmd.exe`, `certutil` and `findstr` are out of the picture
//! entirely.
//!
//! The pipe is created by the child, not the parent: the parent would otherwise
//! block waiting for a child that may never appear because the user dismissed
//! the UAC prompt.
//!
//! The token exists because the pipe hands out administrator rights. The child
//! compares the pid of whoever connects with the pid passed here, and then
//! expects the token as the first line of the stream. A process running as the
//! same user can read the token off the child's command line, so the pid check
//! is the real barrier; the token binds the bytes to this launch.

use super::{
    installer_exec::{
        EXIT_BAD_ARGUMENTS, EXIT_COMMAND_FAILED, EXIT_PIPE_FAILED, EXIT_UNAUTHORIZED,
    },
    installer_shell::{spawn_elevated_self, wait_process},
    validate_install_app_name, ResultType,
};
use hbb_common::{bail, log};
use std::time::{Duration, Instant};
use windows::{
    core::PCWSTR,
    Win32::{
        Foundation::{CloseHandle, GENERIC_WRITE, HANDLE},
        Storage::FileSystem::{
            CreateFileW, WriteFile, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_NONE, OPEN_EXISTING,
        },
        System::Pipes::WaitNamedPipeW,
    },
};

/// Exit codes reported by the elevated side, kept for the failure messages.
fn elevated_install_failure_reason(exit_code: i32) -> &'static str {
    match exit_code {
        EXIT_PIPE_FAILED => "the elevated setup step could not open its command pipe",
        EXIT_BAD_ARGUMENTS => "the elevated setup step received bad arguments",
        EXIT_UNAUTHORIZED => "the elevated setup step did not recognise this process as its caller",
        EXIT_COMMAND_FAILED => "one or more installer commands failed; see the log",
        _ => "installer command failed",
    }
}

fn pipe_name() -> String {
    format!("nexdesk-setup-{}", uuid::Uuid::new_v4().simple())
}

/// The token the elevated side demands as the first line of the stream.
///
/// A v4 UUID is 122 bits from the system random generator - enough that the
/// value cannot be guessed, which is all this check needs.
fn handshake_token() -> String {
    uuid::Uuid::new_v4().simple().to_string()
}

/// Command line for the elevated copy. Field order is a contract with
/// `core_main`; a missing or extra field fails the install with no diagnostics
/// at all, so it is built in one place and asserted by a test.
fn elevated_parameters(pipe: &str, token: &str, parent_pid: u32) -> String {
    format!("--elevated-setup {pipe} {token} {parent_pid}")
}

/// The token, a newline, then the command text untouched.
fn handshake_payload(token: &str, commands: &str) -> String {
    format!("{token}\n{commands}")
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Waits for the elevated child to publish its pipe, then opens it.
fn connect(pipe: &str, deadline: Instant) -> ResultType<HANDLE> {
    let full = wide(&format!(r"\\.\pipe\{pipe}"));
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            bail!("The elevated installer never opened its command pipe");
        }
        let wait_ms = remaining.as_millis().min(u32::MAX as u128) as u32;
        // Returns zero on timeout, which just means "not yet".
        let _ = unsafe { WaitNamedPipeW(PCWSTR(full.as_ptr()), wait_ms) };
        match unsafe {
            CreateFileW(
                PCWSTR(full.as_ptr()),
                GENERIC_WRITE.0,
                FILE_SHARE_NONE,
                None,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                None,
            )
        } {
            Ok(handle) => return Ok(handle),
            Err(_) => {
                if Instant::now() >= deadline {
                    bail!("The elevated installer never opened its command pipe");
                }
                std::thread::sleep(Duration::from_millis(50));
            }
        }
    }
}

fn write_all(handle: HANDLE, mut data: &[u8]) -> ResultType<()> {
    while !data.is_empty() {
        let mut written = 0u32;
        unsafe { WriteFile(handle, Some(data), Some(&mut written), None)? };
        if written == 0 {
            bail!("The elevated installer closed its command pipe early");
        }
        data = &data[written as usize..];
    }
    Ok(())
}

fn run_elevated_commands(commands: &str, show: bool) -> ResultType<u32> {
    let pipe = pipe_name();
    let token = handshake_token();
    let parent_pid = std::process::id();
    let parameters = elevated_parameters(&pipe, &token, parent_pid);
    // Start first: the child creates the pipe, so connecting before it exists
    // would just spin.
    let process = spawn_elevated_self(&parameters, show)?;
    let deadline = Instant::now() + Duration::from_secs(30);
    let handle = connect(&pipe, deadline)?;
    let payload = handshake_payload(&token, commands);
    let written = write_all(handle, payload.as_bytes());
    unsafe {
        let _ = CloseHandle(handle);
    }
    // Closing the write end is what tells the child the text is complete.
    written?;
    wait_process(process)
}

pub(super) fn run_cmds(cmds: String, show: bool, tip: &str) -> ResultType<()> {
    validate_install_app_name(&crate::get_app_name())?;
    let exit_code = match run_elevated_commands(&cmds, show) {
        Ok(code) => code,
        Err(err) => {
            log::error!("Failed to start the elevated installer for {tip}: {err}");
            return Err(err);
        }
    };
    let exit_code = exit_code as i32;
    if exit_code != 0 {
        bail!(
            "{tip} failed with elevated exit code {exit_code}: {}",
            elevated_install_failure_reason(exit_code)
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pipe_names_are_unique_and_well_formed() {
        let a = pipe_name();
        let b = pipe_name();
        assert_ne!(a, b);
        assert!(a.starts_with("nexdesk-setup-"));
        assert!(a.len() > "nexdesk-setup-".len() + 16);
        assert!(!a.contains('\\'));
    }

    #[test]
    fn every_exit_code_has_its_own_message() {
        let messages = [
            elevated_install_failure_reason(EXIT_PIPE_FAILED),
            elevated_install_failure_reason(EXIT_BAD_ARGUMENTS),
            elevated_install_failure_reason(EXIT_UNAUTHORIZED),
            elevated_install_failure_reason(EXIT_COMMAND_FAILED),
        ];
        for (i, a) in messages.iter().enumerate() {
            for b in messages.iter().skip(i + 1) {
                assert_ne!(a, b, "exit codes must not share a message");
            }
        }
        assert!(elevated_install_failure_reason(EXIT_COMMAND_FAILED).contains("log"));
    }

    #[test]
    fn the_token_is_unguessable_and_unique() {
        let a = handshake_token();
        let b = handshake_token();
        assert_ne!(a, b, "two installs must not share a token");
        assert_eq!(a.len(), 32, "a v4 uuid in simple form is 32 hex digits");
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        // The command line is whitespace-separated, so a space would split it.
        assert!(!a.contains(char::is_whitespace));
    }

    #[test]
    fn the_elevated_command_line_has_exactly_four_fields() {
        let token = "9f2c4b1e8a7d4c0fb3e5a6d7c8b9a0e1";
        let parameters = elevated_parameters("nexdesk-setup-abc", token, 4242);
        assert_eq!(
            parameters,
            format!("--elevated-setup nexdesk-setup-abc {token} 4242")
        );
        let fields: Vec<&str> = parameters.split(' ').collect();
        assert_eq!(fields.len(), 4, "core_main reads args[1..=3]");
        assert_eq!(fields[0], "--elevated-setup");
        assert_eq!(fields[2], token);
        assert_eq!(fields[3], "4242");
    }

    #[test]
    fn the_payload_is_the_token_then_the_commands_verbatim() {
        let token = "abc123";
        let commands = "chcp 65001\r\nreg add HKLM\\X /f\r\n";
        let payload = handshake_payload(token, commands);
        let (first, rest) = payload.split_once('\n').unwrap();
        assert_eq!(first, token);
        // Not even a byte of the command text may be re-encoded on the way.
        assert_eq!(rest, commands);
        // An empty script is still a valid payload: the token line is present,
        // so the child sees a handshake and simply has nothing to execute.
        let empty = handshake_payload(token, "");
        assert_eq!(empty, format!("{token}\n"));
        assert_eq!(empty.split_once('\n').unwrap().1, "");
    }
}
