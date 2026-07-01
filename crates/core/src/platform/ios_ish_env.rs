use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::{c_char, c_int};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

const ROOTFS_VERSION: i32 = 1;
const STDOUT_SIZE: usize = 65_536;
const STDERR_SIZE: usize = 16_384;
const ISH_ERR_ARG_TOO_LONG: i32 = -7;

static ROOTFS_ARCHIVE_PATH: Mutex<Option<String>> = Mutex::new(None);
static MOUNTED_WORKSPACE_DIR: Mutex<Option<String>> = Mutex::new(None);

unsafe extern "C" {
    fn ish_init(rootfs_path: *const c_char) -> c_int;
    fn ish_exec(
        command: *const c_char,
        workdir: *const c_char,
        stdout_buf: *mut c_char,
        stdout_buf_size: usize,
        stderr_buf: *mut c_char,
        stderr_buf_size: usize,
        timeout_ms: c_int,
    ) -> c_int;
    fn ish_is_initialized() -> c_int;
    fn ish_import_rootfs(archive_path: *const c_char, fs_path: *const c_char) -> c_int;
    fn ish_mount_host(host_path: *const c_char, mount_point: *const c_char) -> c_int;
    fn ish_shutdown();
}

#[derive(Debug, Clone)]
pub struct IshCommandResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
    pub error: Option<String>,
}

struct IshEnvPaths {
    rootfs_dir: PathBuf,
    workspace_dir: PathBuf,
    skills_dir: PathBuf,
}

impl IshEnvPaths {
    fn new(files_dir: &str) -> Self {
        Self::new_with_workspace_files_dir(files_dir, files_dir)
    }

    fn new_with_workspace_files_dir(files_dir: &str, workspace_files_dir: &str) -> Self {
        let files = PathBuf::from(files_dir);
        let workspace_files = PathBuf::from(workspace_files_dir);
        let rootfs_dir = files
            .parent()
            .map(|parent| parent.join("ish-rootfs"))
            .unwrap_or_else(|| files.join("ish-rootfs"));
        Self {
            rootfs_dir,
            workspace_dir: workspace_files.join("linux-env").join("workspace"),
            skills_dir: files.join("prompt_skills"),
        }
    }

    fn version_file(&self) -> PathBuf {
        self.rootfs_dir.join(".version")
    }
}

pub fn register_rootfs_archive_path(path: &str) {
    if let Ok(mut guard) = ROOTFS_ARCHIVE_PATH.lock() {
        *guard = Some(path.to_string());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_ios_ish_register_rootfs_archive_path(path: *const c_char) {
    if path.is_null() {
        return;
    }
    let Ok(path) = (
        // SAFETY: `path` is non-null (checked above) and, by this `extern "C"`
        // entrypoint's contract, points to a valid NUL-terminated C string owned
        // by the iOS caller for the duration of the call.
        unsafe { CStr::from_ptr(path) }
    )
    .to_str() else {
        return;
    };
    register_rootfs_archive_path(path);
}

pub fn setup(files_dir: &str) -> anyhow::Result<()> {
    let paths = IshEnvPaths::new(files_dir);
    ensure_rootfs(&paths)?;

    // SAFETY: `ish_is_initialized` takes no arguments and only reads the iSH
    // kernel's global init flag; it is always sound to call.
    if unsafe { ish_is_initialized() } == 0 {
        let rootfs = CString::new(paths.rootfs_dir.to_string_lossy().as_ref())?;
        // SAFETY: `rootfs` is a valid NUL-terminated C string that outlives the
        // call; `ish_init` reads it and returns a status code.
        let err = unsafe { ish_init(rootfs.as_ptr()) };
        if err < 0 {
            anyhow::bail!("iSH kernel init failed with error {}", err);
        }
        clear_mounted_workspace_dir();
    }

    configure_dns()?;
    mount_host_dirs(&paths)?;
    Ok(())
}

pub fn is_ready(files_dir: &str) -> bool {
    let paths = IshEnvPaths::new(files_dir);
    // SAFETY: `ish_is_initialized` takes no arguments and only reads the iSH
    // kernel's global init flag; it is always sound to call.
    (unsafe { ish_is_initialized() != 0 }) && rootfs_exists(&paths)
}

pub fn execute(command: &str, workdir: Option<&str>, timeout_ms: i32) -> IshCommandResult {
    // SAFETY: `ish_is_initialized` takes no arguments and only reads the iSH
    // kernel's global init flag; it is always sound to call.
    if unsafe { ish_is_initialized() } == 0 {
        return IshCommandResult {
            exit_code: -1,
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            error: Some("iSH kernel not initialized".to_string()),
        };
    }

    let command = match CString::new(command) {
        Ok(command) => command,
        Err(e) => {
            return IshCommandResult {
                exit_code: -1,
                stdout: String::new(),
                stderr: String::new(),
                timed_out: false,
                error: Some(format!("invalid command: {}", e)),
            };
        }
    };
    let workdir = match workdir {
        Some(workdir) if !workdir.is_empty() => match CString::new(workdir) {
            Ok(workdir) => Some(workdir),
            Err(e) => {
                return IshCommandResult {
                    exit_code: -1,
                    stdout: String::new(),
                    stderr: String::new(),
                    timed_out: false,
                    error: Some(format!("invalid workdir: {}", e)),
                };
            }
        },
        _ => None,
    };

    let mut stdout_buf = vec![0 as c_char; STDOUT_SIZE];
    let mut stderr_buf = vec![0 as c_char; STDERR_SIZE];
    // SAFETY: `command`/`workdir` are valid NUL-terminated C strings (or null for
    // workdir) that outlive the call, and the two output buffers are live, owned
    // allocations whose pointer/length pairs are passed correctly for `ish_exec`
    // to fill. The call only borrows them for its duration.
    let exit_code = unsafe {
        ish_exec(
            command.as_ptr(),
            workdir
                .as_ref()
                .map(|s| s.as_ptr())
                .unwrap_or(std::ptr::null()),
            stdout_buf.as_mut_ptr(),
            stdout_buf.len(),
            stderr_buf.as_mut_ptr(),
            stderr_buf.len(),
            timeout_ms,
        )
    };

    // SAFETY: `ish_exec` NUL-terminates `stdout_buf`, which remains a live,
    // owned allocation here, so reading it as a C string is valid.
    let stdout = unsafe { CStr::from_ptr(stdout_buf.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    // SAFETY: `ish_exec` NUL-terminates `stderr_buf`, which remains a live,
    // owned allocation here, so reading it as a C string is valid.
    let stderr = unsafe { CStr::from_ptr(stderr_buf.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    let stdout = strip_ansi_codes(&stdout);
    let stderr = strip_ansi_codes(&stderr);

    if exit_code == -4 {
        return IshCommandResult {
            exit_code: -1,
            stdout,
            stderr,
            timed_out: true,
            error: Some(format!("Command timed out after {}ms", timeout_ms)),
        };
    }

    if exit_code < 0 {
        let error = if exit_code == ISH_ERR_ARG_TOO_LONG {
            "Command is too long for the iOS Linux executor".to_string()
        } else {
            format!("Execution error: {}", exit_code)
        };
        return IshCommandResult {
            exit_code,
            stdout,
            stderr,
            timed_out: false,
            error: Some(error),
        };
    }

    IshCommandResult {
        exit_code,
        stdout,
        stderr,
        timed_out: false,
        error: None,
    }
}

pub fn execute_in_workspace(
    files_dir: &str,
    workspace_files_dir: &str,
    command: &str,
    workdir: Option<&str>,
    timeout_ms: i32,
) -> IshCommandResult {
    // SAFETY: `ish_is_initialized` takes no arguments and only reads the iSH
    // kernel's global init flag; it is always sound to call.
    if unsafe { ish_is_initialized() } == 0 {
        if let Err(error) = setup(files_dir) {
            return IshCommandResult {
                exit_code: -1,
                stdout: String::new(),
                stderr: String::new(),
                timed_out: false,
                error: Some(error.to_string()),
            };
        }
    }

    let paths = IshEnvPaths::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    if let Err(error) = mount_workspace_dir(&paths.workspace_dir) {
        return IshCommandResult {
            exit_code: -1,
            stdout: String::new(),
            stderr: String::new(),
            timed_out: false,
            error: Some(error.to_string()),
        };
    }

    execute(command, workdir, timeout_ms)
}

pub fn shutdown() {
    // SAFETY: `ish_shutdown` takes no arguments and tears down the iSH kernel's
    // global state; it is sound to call regardless of init state.
    unsafe { ish_shutdown() };
    clear_mounted_workspace_dir();
}

fn ensure_rootfs(paths: &IshEnvPaths) -> anyhow::Result<()> {
    if rootfs_exists(paths) && is_version_current(paths) {
        return Ok(());
    }

    if paths.rootfs_dir.exists() {
        fs::remove_dir_all(&paths.rootfs_dir)?;
    }

    let archive_path = ROOTFS_ARCHIVE_PATH
        .lock()
        .map_err(|e| anyhow::anyhow!("rootfs archive lock poisoned: {}", e))?
        .clone()
        .ok_or_else(|| anyhow::anyhow!("iSH rootfs archive path not registered"))?;
    let archive = CString::new(archive_path)?;
    let target = CString::new(paths.rootfs_dir.to_string_lossy().as_ref())?;
    // SAFETY: `archive` and `target` are valid NUL-terminated C strings that
    // outlive the call; `ish_import_rootfs` reads both and returns a status code.
    let result = unsafe { ish_import_rootfs(archive.as_ptr(), target.as_ptr()) };
    if result != 0 {
        let _ = fs::remove_dir_all(&paths.rootfs_dir);
        anyhow::bail!("ish_import_rootfs failed: {}", result);
    }

    if !rootfs_exists(paths) {
        anyhow::bail!("iSH rootfs import finished but data or meta.db is missing");
    }

    write_version_marker(paths)?;
    Ok(())
}

fn rootfs_exists(paths: &IshEnvPaths) -> bool {
    paths.rootfs_dir.join("data").exists() && paths.rootfs_dir.join("meta.db").exists()
}

fn is_version_current(paths: &IshEnvPaths) -> bool {
    let Ok(version) = fs::read_to_string(paths.version_file()) else {
        return false;
    };
    version
        .trim()
        .parse::<i32>()
        .map(|version| version >= ROOTFS_VERSION)
        .unwrap_or(false)
}

fn write_version_marker(paths: &IshEnvPaths) -> anyhow::Result<()> {
    fs::write(paths.version_file(), ROOTFS_VERSION.to_string())?;
    Ok(())
}

fn configure_dns() -> anyhow::Result<()> {
    let dns_config = match host_dns_config() {
        Ok(config) => config,
        Err(error) => {
            log::warn!("Cannot read iOS host DNS config: {error}");
            fallback_dns_config()
        }
    };
    let escaped = shell_single_quote(&dns_config);
    let command = format!("printf %s {escaped} > /etc/resolv.conf");
    let result = execute(&command, None, 5_000);
    if result.exit_code < 0 {
        anyhow::bail!(
            "failed to configure iSH DNS: {}",
            result.error.unwrap_or_else(|| result.stderr)
        );
    }
    Ok(())
}

fn host_dns_config() -> anyhow::Result<String> {
    let content = fs::read_to_string("/etc/resolv.conf")?;
    let nameservers: Vec<&str> = content
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                return None;
            }
            line.strip_prefix("nameserver").map(str::trim)
        })
        .filter(|value| !value.is_empty() && *value != "0.0.0.0")
        .collect();
    if nameservers.is_empty() {
        anyhow::bail!("host resolv.conf has no usable nameservers");
    }
    Ok(nameservers
        .iter()
        .map(|nameserver| format!("nameserver {nameserver}"))
        .collect::<Vec<_>>()
        .join("\n")
        + "\n")
}

fn fallback_dns_config() -> String {
    "nameserver 8.8.8.8\nnameserver 1.1.1.1\n".to_string()
}

fn shell_single_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn mount_host_dirs(paths: &IshEnvPaths) -> anyhow::Result<()> {
    fs::create_dir_all(&paths.workspace_dir)?;
    fs::create_dir_all(&paths.skills_dir)?;
    mount_host_dir(&paths.skills_dir, "/skills")?;
    mount_workspace_dir(&paths.workspace_dir)?;
    Ok(())
}

fn mount_workspace_dir(workspace_dir: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(workspace_dir)?;
    let workspace = workspace_dir.to_string_lossy().to_string();
    let mut mounted = MOUNTED_WORKSPACE_DIR
        .lock()
        .map_err(|e| anyhow::anyhow!("iSH workspace mount lock poisoned: {}", e))?;
    if mounted.as_deref() == Some(workspace.as_str()) {
        return Ok(());
    }
    mount_host_dir(workspace_dir, "/workspace")?;
    *mounted = Some(workspace);
    Ok(())
}

fn clear_mounted_workspace_dir() {
    if let Ok(mut mounted) = MOUNTED_WORKSPACE_DIR.lock() {
        *mounted = None;
    }
}

fn mount_host_dir(host_path: &Path, mount_point: &str) -> anyhow::Result<()> {
    let host_path = CString::new(host_path.to_string_lossy().as_ref())?;
    let mount_point = CString::new(mount_point)?;
    // SAFETY: `host_path` and `mount_point` are valid NUL-terminated C strings
    // that outlive the call; `ish_mount_host` reads both and returns a status.
    let result = unsafe { ish_mount_host(host_path.as_ptr(), mount_point.as_ptr()) };
    if result < 0 {
        anyhow::bail!(
            "ish_mount_host failed for {}: {}",
            mount_point.to_string_lossy(),
            result
        );
    }
    Ok(())
}

fn strip_ansi_codes(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch != '\u{1b}' {
            output.push(ch);
            continue;
        }
        match chars.peek().copied() {
            Some('[') => {
                chars.next();
                for next in chars.by_ref() {
                    if next.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            Some('(') => {
                chars.next();
                chars.next();
            }
            Some('=') | Some('>') => {
                chars.next();
            }
            _ => {}
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::{IshEnvPaths, shell_single_quote};
    use std::path::PathBuf;

    #[test]
    fn scoped_workspace_path_uses_selected_agent_scope() {
        let paths = IshEnvPaths::new_with_workspace_files_dir(
            "/app/files",
            "/app/files/napaxi_scopes/accounts/acct-a/agents/agent-a",
        );

        assert_eq!(paths.rootfs_dir, PathBuf::from("/app/ish-rootfs"));
        assert_eq!(paths.skills_dir, PathBuf::from("/app/files/prompt_skills"));
        assert_eq!(
            paths.workspace_dir,
            PathBuf::from(
                "/app/files/napaxi_scopes/accounts/acct-a/agents/agent-a/linux-env/workspace"
            )
        );
    }

    #[test]
    fn shell_single_quote_escapes_embedded_quotes() {
        assert_eq!(
            shell_single_quote("nameserver 1.1.1.1\nsearch user's-lan\n"),
            "'nameserver 1.1.1.1\nsearch user'\\''s-lan\n'"
        );
    }
}
