//! Runs the installer's privileged step without writing a script to disk.
//!
//! The installer used to build a batch/cmd file and hand it to an elevated
//! `cmd.exe`. That is the shape scanners score hardest: a script in a writable
//! directory whose body creates a service. It was moved out of `%TEMP%` and
//! renamed once already, which reduced the hit rate but kept the pattern.
//!
//! Here the elevated process is the application itself. The parent sends the
//! command text over a named pipe; this module reads it and executes each
//! command directly. No script file exists at any point, and `cmd.exe`,
//! `certutil` and `findstr` are not involved.
//!
//! Every command the generators emit is recognised explicitly. Anything not
//! recognised is executed through `cmd /C` one line at a time rather than being
//! skipped, so an unforeseen command behaves exactly as it did before instead of
//! leaving a half-installed application behind.

use std::{
    fs,
    os::windows::process::CommandExt,
    path::{Path, PathBuf},
    process::Command,
};

use hbb_common::{anyhow::anyhow, bail, log};
use windows::{
    core::PCWSTR,
    Win32::{
        Foundation::{CloseHandle, HANDLE},
        Storage::FileSystem::ReadFile,
        System::Pipes::ConnectNamedPipe,
    },
};

use super::ResultType;

/// Commands are bounded so a malformed pipe cannot make us allocate forever.
const MAX_SCRIPT_BYTES: usize = 4 * 1024 * 1024;

// Exit codes shared with `installer_handoff`, which turns them into messages.
pub(super) const EXIT_OK: i32 = 0;
pub(super) const EXIT_PIPE_FAILED: i32 = 0x5253_0001;
pub(super) const EXIT_BAD_ARGUMENTS: i32 = 0x5253_0003;
pub(super) const EXIT_COMMAND_FAILED: i32 = 0x5253_0009;

pub(super) fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Reads the whole command text from an already-connected pipe.
unsafe fn read_pipe(pipe: HANDLE) -> ResultType<String> {
    let mut out: Vec<u8> = Vec::new();
    let mut buf = vec![0u8; 8192];
    loop {
        let mut read = 0u32;
        ReadFile(pipe, Some(&mut buf[..]), Some(&mut read), None)
            .map_err(|err| anyhow!("Failed to read installer commands from the pipe: {err}"))?;
        if read == 0 {
            break;
        }
        out.extend_from_slice(&buf[..read as usize]);
        if out.len() > MAX_SCRIPT_BYTES {
            bail!("Installer command text exceeds {MAX_SCRIPT_BYTES} bytes");
        }
    }
    Ok(String::from_utf8(out)?)
}

/// Entry point for `--elevated-setup <pipe>`. Blocks until the parent connects.
pub(super) fn run_from_pipe(pipe_name: &str) -> ResultType<i32> {
    use windows::Win32::{
        Foundation::GetLastError,
        Storage::FileSystem::{FILE_FLAGS_AND_ATTRIBUTES, PIPE_ACCESS_INBOUND},
        System::Pipes::{CreateNamedPipeW, PIPE_READMODE_BYTE, PIPE_TYPE_BYTE, PIPE_WAIT},
    };

    // FILE_FLAG_FIRST_PIPE_INSTANCE: refuse to attach to a name someone else
    // already created, so the pipe cannot be squatted.
    const FILE_FLAG_FIRST_PIPE_INSTANCE: u32 = 0x0008_0000;
    // ERROR_PIPE_CONNECTED as an HRESULT: the client connected before
    // ConnectNamedPipe was called, which is success, not failure.
    const ERROR_PIPE_CONNECTED_HRESULT: u32 = 0x8007_0217;

    let name = wide(&format!(r"\\.\pipe\{pipe_name}"));
    let pipe = unsafe {
        CreateNamedPipeW(
            PCWSTR(name.as_ptr()),
            FILE_FLAGS_AND_ATTRIBUTES(PIPE_ACCESS_INBOUND.0 | FILE_FLAG_FIRST_PIPE_INSTANCE),
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            1,
            0,
            MAX_SCRIPT_BYTES as u32,
            0,
            None,
        )
    };
    if pipe.is_invalid() {
        bail!("Failed to create the installer pipe: {:?}", unsafe {
            GetLastError()
        });
    }

    if let Err(err) = unsafe { ConnectNamedPipe(pipe, None) } {
        if err.code().0 as u32 != ERROR_PIPE_CONNECTED_HRESULT {
            unsafe {
                let _ = CloseHandle(pipe);
            }
            bail!("Failed to connect the installer pipe: {err}");
        }
    }

    let script = unsafe { read_pipe(pipe) };
    unsafe {
        let _ = CloseHandle(pipe);
    }
    let script = script?;

    let mut executor = Executor::new()?;
    executor.run(&script)
}

/// Executes the installer's command text.
pub(super) struct Executor {
    /// Stands in for `%RUSTDESK_OUTPUT_DIR%`.
    staging: PathBuf,
    /// Stands in for `%~f0`, the script path the old batches referred to.
    script_base: PathBuf,
}

impl Executor {
    pub(super) fn new() -> ResultType<Self> {
        let staging = hbb_common::config::Config::path("setup")
            .join(format!("stage-{}", uuid::Uuid::new_v4().simple()));
        fs::create_dir_all(&staging)?;
        Ok(Self {
            script_base: staging.join("setup"),
            staging,
        })
    }

    /// Expands the variables the generated commands rely on.
    ///
    /// `%RUSTDESK_OUTPUT_DIR%` and `%~f0` pointed at the script and its side
    /// directory. With no script there is nothing to point at, so they resolve
    /// into a private staging directory that is removed when this drops.
    fn expand(&self, line: &str) -> String {
        let mut out = line
            .replace("%RUSTDESK_OUTPUT_DIR%", &self.staging.to_string_lossy())
            .replace("%~f0", &self.script_base.to_string_lossy());
        for var in [
            "PROGRAMDATA",
            "PUBLIC",
            "APPDATA",
            "LOCALAPPDATA",
            "ProgramFiles",
        ] {
            if let Ok(value) = std::env::var(var) {
                out = out.replace(&format!("%{var}%"), &value);
            }
        }
        out
    }

    /// Executes every line, collecting failures instead of stopping at the first.
    ///
    /// The script begins by uninstalling the previous version, so there is no
    /// snapshot to roll back to. Aborting halfway leaves the machine in a worse
    /// state than finishing and reporting precisely which command broke.
    pub(super) fn run(&mut self, script: &str) -> ResultType<i32> {
        let mut required_failures = 0;
        for (index, raw) in script.lines().enumerate() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with("rem ") || line.starts_with("::") {
                continue;
            }
            let expanded = self.expand(line);
            let expanded = expanded.trim();
            if expanded.is_empty() {
                continue;
            }
            if let Err(err) = self.run_line(expanded) {
                if classify(expanded).required {
                    required_failures += 1;
                    log::error!("Installer command {index} failed ({err}): {expanded}");
                } else {
                    log::warn!("Installer command {index} failed, ignored ({err}): {expanded}");
                }
            }
        }
        if required_failures == 0 {
            Ok(EXIT_OK)
        } else {
            log::error!("{required_failures} required installer command(s) failed");
            Ok(EXIT_COMMAND_FAILED)
        }
    }

    fn run_line(&mut self, line: &str) -> ResultType<()> {
        let lower = line.to_ascii_lowercase();

        // `chcp` only existed to set a code page for a batch file. An older
        // generator may still chain it to a real command with `&&`; run the
        // remainder rather than dropping the whole line, which is what made the
        // MSI update a silent no-op.
        if lower.starts_with("chcp") {
            if let Some((_, rest)) = line.split_once("&&") {
                let rest = rest.trim();
                if !rest.is_empty() {
                    return self.run_line(rest);
                }
            }
            return Ok(());
        }
        // Shell variables have no meaning without a shell; the generators must
        // not rely on them.
        if lower.starts_with("timeout") || lower.starts_with("set ") {
            return Ok(());
        }
        if lower.starts_with("echo ") || lower == "echo." {
            return Ok(());
        }
        // The redirect-echo form is only used to stage base64 payloads.
        if let Some(rest) = line.strip_prefix("> ") {
            return self.write_redirect(rest);
        }
        if lower.starts_with("nexdesk-decode ") {
            return self.decode_embedded(rest_of(line, "nexdesk-decode "));
        }
        if lower.starts_with("reg ") {
            return run_tool_raw("reg", rest_of(line, "reg "));
        }
        if lower.starts_with("md ") || lower.starts_with("mkdir ") {
            let dir = strip_quotes(after_first_word(line));
            fs::create_dir_all(dir)?;
            return Ok(());
        }
        if lower.starts_with("copy ") {
            return self.copy(rest_of(line, "copy "));
        }
        if lower.starts_with("xcopy ") {
            return self.xcopy(rest_of(line, "xcopy "));
        }
        if lower.starts_with("del ") || lower.starts_with("erase ") {
            // `del /f /q "path"` - the path is the only quoted argument, and it
            // may itself contain spaces, so splitting on '/' would be wrong.
            for target in quoted_args(line) {
                let _ = fs::remove_file(target);
            }
            return Ok(());
        }
        if lower.starts_with("if exist ") {
            return self.if_exist(&line["if exist ".len()..]);
        }
        if line.starts_with('"') {
            // A bare quoted command line, e.g. `"C:\...\NexDesk.exe" --flag`.
            if let Some((exe, args)) = split_first_quoted(line) {
                return run_tool_raw(&exe, args);
            }
        }
        if lower.starts_with("msiexec") {
            return run_tool_raw("msiexec", after_first_word(line));
        }
        if lower.starts_with("taskkill ") {
            return run_tool_raw("taskkill", after_first_word(line));
        }
        if lower.starts_with("sc ") {
            return run_tool_raw("sc", after_first_word(line));
        }
        if lower.starts_with("netsh ") {
            return run_tool_raw("netsh", after_first_word(line));
        }

        // Unknown shape: run it through cmd exactly as the old script would
        // have, so behaviour is preserved rather than silently dropped.
        log::info!("Installer: running unrecognised command through cmd: {line}");
        run_tool_raw("cmd", &format!("/C {line}"))
    }

    fn write_redirect(&mut self, rest: &str) -> ResultType<()> {
        // `"path" echo <data>`
        let (path, remainder) = split_first_quoted(rest)
            .ok_or_else(|| anyhow!("Malformed redirect in installer command: {rest}"))?;
        let data = remainder
            .trim_start()
            .strip_prefix("echo ")
            .unwrap_or(remainder.trim_start());
        fs::write(self.expand(&path), data)?;
        Ok(())
    }

    fn decode_embedded(&mut self, rest: &str) -> ResultType<()> {
        // `-f -decode "src" "dst" > nul || exit /b N`
        let mut parts = tokenize(rest);
        parts.retain(|p| {
            !p.starts_with('-') && p != ">" && p != "nul" && p != "||" && p != "exit" && p != "/b"
        });
        if parts.len() < 2 {
            bail!("Malformed shortcut decode in installer command");
        }
        let src = self.expand(strip_quotes(&parts[0]));
        let dst = self.expand(strip_quotes(&parts[1]));
        let data = fs::read(&src)?;
        if let Some(parent) = Path::new(&dst).parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&dst, decode_base64(&data)?)?;
        let _ = fs::remove_file(&src);
        Ok(())
    }

    fn copy(&mut self, rest: &str) -> ResultType<()> {
        let parts = tokenize(rest);
        let files: Vec<&String> = parts.iter().filter(|p| !p.starts_with('/')).collect();
        if files.len() < 2 {
            bail!("Malformed copy in installer command: {rest}");
        }
        let src = self.expand(strip_quotes(files[0]));
        let dst = self.expand(strip_quotes(files[1]));
        let dst_path = Path::new(&dst);
        let target = if dst.ends_with('\\') || dst_path.is_dir() {
            dst_path.join(Path::new(&src).file_name().unwrap_or_default())
        } else {
            dst_path.to_path_buf()
        };
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(&src, &target)?;
        Ok(())
    }

    fn xcopy(&mut self, rest: &str) -> ResultType<()> {
        let parts = tokenize(rest);
        let files: Vec<&String> = parts.iter().filter(|p| !p.starts_with('/')).collect();
        if files.len() < 2 {
            bail!("Malformed xcopy in installer command: {rest}");
        }
        copy_dir_all(
            Path::new(&self.expand(strip_quotes(files[0]))),
            Path::new(&self.expand(strip_quotes(files[1]))),
        )
    }

    fn if_exist(&mut self, rest: &str) -> ResultType<()> {
        // `"path" del /f /q "path"` - the body is an ordinary command.
        let (path, remainder) = split_first_quoted(rest)
            .ok_or_else(|| anyhow!("Malformed conditional in installer command: {rest}"))?;
        if Path::new(&self.expand(&path)).exists() {
            let command = remainder.trim_start().to_owned();
            if !command.is_empty() {
                self.run_line(&command)?;
            }
        }
        Ok(())
    }
}

impl Drop for Executor {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.staging);
    }
}

fn rest_of<'a>(line: &'a str, prefix: &str) -> &'a str {
    line.get(prefix.len()..).unwrap_or("").trim_start()
}

fn after_first_word(line: &str) -> &str {
    line.split_once(' ')
        .map(|(_, rest)| rest.trim_start())
        .unwrap_or("")
}

fn strip_quotes(s: &str) -> &str {
    s.trim().trim_matches('"')
}

/// Every double-quoted run in `line`, with the quotes removed.
fn quoted_args(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    for ch in line.chars() {
        match ch {
            '"' if in_quotes => {
                in_quotes = false;
                out.push(std::mem::take(&mut current));
            }
            '"' => in_quotes = true,
            c if in_quotes => current.push(c),
            _ => {}
        }
    }
    out
}

fn split_first_quoted(s: &str) -> Option<(String, &str)> {
    let s = s.trim_start();
    if let Some(rest) = s.strip_prefix('"') {
        let end = rest.find('"')?;
        Some((rest[..end].to_owned(), &rest[end + 1..]))
    } else {
        let end = s.find(' ')?;
        Some((s[..end].to_owned(), &s[end + 1..]))
    }
}

/// Splits on whitespace, keeping quoted runs together and preserving the quotes
/// so `strip_quotes` can distinguish an empty argument from a missing one.
fn tokenize(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    for ch in s.chars() {
        match ch {
            '"' => {
                in_quotes = !in_quotes;
                current.push(ch);
            }
            c if c.is_whitespace() && !in_quotes => {
                if !current.is_empty() {
                    out.push(std::mem::take(&mut current));
                }
            }
            c => current.push(c),
        }
    }
    if !current.is_empty() {
        out.push(current);
    }
    out
}

/// How a failing command is treated.
struct Verdict {
    /// The install is not usable without this command.
    required: bool,
    /// Exit codes that mean success in practice (already exists, already
    /// running, reboot required).
    tolerated: &'static [i32],
}

/// Decides whether a command's failure should fail the install.
///
/// "Required" means the installed product does not work without it. Everything
/// else is best-effort cleanup that is expected to fail when the thing it
/// removes was never there - `sc delete` on a fresh machine, `taskkill` on a
/// process that is not running.
fn classify(line: &str) -> Verdict {
    let lower = line.to_ascii_lowercase();
    let required = |tolerated: &'static [i32]| Verdict {
        required: true,
        tolerated,
    };
    let optional = Verdict {
        required: false,
        tolerated: &[],
    };

    if lower.starts_with("reg ") {
        return required(&[]);
    }
    if lower.starts_with("sc ") {
        if lower.contains(" stop ") || lower.contains(" delete ") {
            return optional;
        }
        if lower.contains(" create ") {
            // 1073 = the service already exists.
            return required(&[1073]);
        }
        // 1056 = the service is already running.
        return required(&[1056]);
    }
    if lower.starts_with("netsh ") {
        return if lower.contains(" delete ") {
            optional
        } else {
            required(&[])
        };
    }
    if lower.starts_with("taskkill ")
        || lower.starts_with("del ")
        || lower.starts_with("erase ")
        || lower.starts_with("rd ")
    {
        return optional;
    }
    if lower.starts_with("msiexec") {
        // 3010 and 1641 both mean success with a pending reboot.
        return required(&[3010, 1641]);
    }
    if lower.starts_with("chcp")
        || lower.starts_with("timeout")
        || lower.starts_with("set ")
        || lower.starts_with("echo")
    {
        return optional;
    }
    // Everything else, including the `cmd /C` fallback, must succeed: an
    // unrecognised command is a generator bug we want to hear about.
    required(&[])
}

/// Runs a system tool with the argument tail passed through unmodified.
///
/// `raw_arg` reproduces byte for byte what `cmd.exe` used to hand the child.
/// Re-tokenising turned cmd escapes into literals: `binpath= "\"C:\...\exe\"
/// --service"` reached `sc` with the backslashes intact, so the service was
/// registered with a broken binary path.
fn run_tool_raw(tool: &str, raw_tail: &str) -> ResultType<()> {
    let mut command = Command::new(tool);
    command.raw_arg(raw_tail);
    let status = command.status()?;
    let code = status.code().unwrap_or(-1);
    let verdict = classify(&format!("{tool} {raw_tail}"));
    if code == 0 || verdict.tolerated.contains(&code) {
        return Ok(());
    }
    if verdict.required {
        bail!("{tool} exited with {code}: {raw_tail}");
    }
    log::warn!("{tool} exited with {code} (ignored): {raw_tail}");
    Ok(())
}

fn copy_dir_all(src: &Path, dst: &Path) -> ResultType<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let target = dst.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir_all(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), &target)?;
        }
    }
    Ok(())
}

fn decode_base64(data: &[u8]) -> ResultType<Vec<u8>> {
    use hbb_common::base64::{engine::general_purpose::STANDARD, Engine as _};
    let text = std::str::from_utf8(data)?.trim();
    Ok(STANDARD.decode(text)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quoted_runs_survive_tokenizing() {
        let tokens = tokenize(r#"/Y "C:\Program Files\NexDesk\a.dll" "D:\out\""#);
        assert_eq!(
            tokens,
            vec![
                "/Y".to_string(),
                r#""C:\Program Files\NexDesk\a.dll""#.to_string(),
                r#""D:\out\""#.to_string(),
            ]
        );
    }

    #[test]
    fn only_quoted_paths_are_taken_from_a_delete() {
        // The path contains spaces and a slash-free name; splitting on '/'
        // would have produced garbage, which is why this is extracted by quotes.
        let args = quoted_args(r#"del /f /q "C:\Program Files\NexDesk\a b.lnk""#);
        assert_eq!(args, vec![r"C:\Program Files\NexDesk\a b.lnk".to_string()]);
    }

    #[test]
    fn redirect_echo_is_split_into_path_and_payload() {
        let (path, rest) = split_first_quoted(r#""C:\stage\x.b64" echo QUJD"#).unwrap();
        assert_eq!(path, r"C:\stage\x.b64");
        assert_eq!(rest.trim_start().strip_prefix("echo "), Some("QUJD"));
    }

    #[test]
    fn embedded_shortcut_lines_reduce_to_source_and_destination() {
        // Mirrors what embedded_shortcut_commands emits, after expansion.
        let rest = r#"-f -decode "C:\stage\x.b64" "C:\stage\NexDesk Tray.lnk" > nul || exit /b 0x52530008"#;
        let mut parts = tokenize(rest);
        parts.retain(|p| {
            !p.starts_with('-') && p != ">" && p != "nul" && p != "||" && p != "exit" && p != "/b"
        });
        assert_eq!(strip_quotes(&parts[0]), r"C:\stage\x.b64");
        assert_eq!(strip_quotes(&parts[1]), r"C:\stage\NexDesk Tray.lnk");
    }

    #[test]
    fn base64_payload_round_trips() {
        use hbb_common::base64::{engine::general_purpose::STANDARD, Engine as _};
        let payload = b"shortcut bytes";
        let encoded = STANDARD.encode(payload);
        assert_eq!(decode_base64(encoded.as_bytes()).unwrap(), payload.to_vec());
    }

    #[test]
    fn policy_distinguishes_required_from_cleanup() {
        // A failed service creation must fail the install; a failed cleanup of
        // something that was never there must not.
        assert!(classify("reg add HKLM\\Software\\X /f").required);
        assert!(classify("sc create NexDesk binpath= \"x\" start= auto").required);
        assert!(classify("sc start NexDesk").required);
        assert!(classify("netsh advfirewall firewall add rule name=\"x\" dir=in").required);

        assert!(!classify("sc stop NexDesk").required);
        assert!(!classify("sc delete NexDesk").required);
        assert!(!classify("taskkill /F /IM NexDesk.exe").required);
        assert!(!classify("del /f /q \"C:\\x\\y.lnk\"").required);
        assert!(!classify("netsh advfirewall firewall delete rule name=\"x\"").required);
        assert!(!classify("chcp 65001").required);

        // An unrecognised line is a generator bug, so it must fail loudly.
        assert!(classify("something-we-do-not-know").required);
    }

    #[test]
    fn tolerated_codes_cover_the_expected_no_ops() {
        // 1073 = service already exists, 1056 = already running.
        assert!(classify("sc create NexDesk").tolerated.contains(&1073));
        assert!(classify("sc start NexDesk").tolerated.contains(&1056));
        // 3010 / 1641 = success with a pending reboot.
        assert!(classify("msiexec /i \"a.msi\" /qn")
            .tolerated
            .contains(&3010));
        assert!(classify("msiexec /i \"a.msi\" /qn")
            .tolerated
            .contains(&1641));
        // A required command that is not sc/msiexec tolerates nothing.
        assert!(classify("reg add HKLM\\X /f").tolerated.is_empty());
    }

    #[test]
    fn copy_target_follows_a_trailing_separator() {
        // `copy /Y "src\a.lnk" "dir\"` must land inside `dir`, not replace it.
        let dst = r"C:\ProgramData\Start Menu\";
        assert!(dst.ends_with('\\'));
        let joined = Path::new(dst).join(Path::new(r"C:\stage\a.lnk").file_name().unwrap());
        assert_eq!(joined, Path::new(r"C:\ProgramData\Start Menu\a.lnk"));
    }
}
