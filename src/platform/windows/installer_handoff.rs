//! Sends the installer's privileged commands to an elevated copy of ourselves.
//!
//! The commands used to be written to a `.cmd` file which an elevated `cmd.exe`
//! then ran. Even after moving that file out of `%TEMP%` and renaming it, the
//! pattern - a script on disk whose body creates a service - is the one scanners
//! score highest, and it produced a real `HEUR/Malware.bat.Gen` detection.
//!
//! There is no script now. The parent creates a named pipe, starts
//! `NexDesk.exe --elevated-setup <pipe>` with the `runas` verb, and writes the
//! command text into that pipe. The elevated copy reads it and executes each
//! command directly (see `installer_exec`). Nothing is staged on disk, and
//! `cmd.exe`, `certutil` and `findstr` are out of the picture entirely.
//!
//! The pipe is created by the child, not the parent: the parent would otherwise
//! block waiting for a child that may never appear because the user dismissed
//! the UAC prompt.

use super::{
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
const ELEVATED_SETUP_FAILED_EXIT_CODE: u32 = 0x5253_0009;

fn pipe_name() -> String {
    format!("nexdesk-setup-{}", uuid::Uuid::new_v4().simple())
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
    let parameters = format!("--elevated-setup {pipe}");
    // Start first: the child creates the pipe, so connecting before it exists
    // would just spin.
    let process = spawn_elevated_self(&parameters, show)?;
    let deadline = Instant::now() + Duration::from_secs(30);
    let handle = connect(&pipe, deadline)?;
    let written = write_all(handle, commands.as_bytes());
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
    if exit_code != 0 {
        bail!(
            "{tip} failed with elevated exit code {exit_code}: {}",
            elevated_install_failure_reason(exit_code)
        );
    }
    Ok(())
}

fn elevated_install_failure_reason(exit_code: u32) -> &'static str {
    match exit_code {
        ELEVATED_SETUP_FAILED_EXIT_CODE => "the elevated setup step reported a failure",
        1223 => "elevation was cancelled",
        _ => "installer command failed",
    }
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
    fn failure_reasons_cover_the_reported_codes() {
        assert!(
            elevated_install_failure_reason(ELEVATED_SETUP_FAILED_EXIT_CODE).contains("elevated")
        );
        assert!(elevated_install_failure_reason(1223).contains("cancelled"));
    }
}
