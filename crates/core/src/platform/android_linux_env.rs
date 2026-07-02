//! Android proot Linux environment setup and command execution.
//!
//! Entry points are only invoked from the Android JNI build of the SDK; on
//! other host targets the symbols are unused, so dead-code lints are silenced
//! off-Android to keep `cargo check` clean on developer machines.
#![cfg_attr(not(target_os = "android"), allow(dead_code))]

#[path = "android_linux_env/pty.rs"]
pub(crate) mod pty;

use std::fs;
use std::io::{Cursor, Read};
#[cfg(unix)]
use std::os::unix::fs as unix_fs;
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Output, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use flate2::read::GzDecoder;
use tar::Archive;

const ROOTFS_VERSION: i32 = 2;
const STANDARD_PROOT_BINDS: &[(&str, &str)] =
    &[("/proc", "/proc"), ("/dev", "/dev"), ("/sys", "/sys")];
pub(super) const PROCESS_EXIT_GRACE: Duration = Duration::from_secs(2);
pub(super) const SIGTERM: i32 = 15;
pub(super) const SIGKILL: i32 = 9;

#[cfg(unix)]
unsafe extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

pub(super) struct LinuxEnvPaths {
    env_dir: PathBuf,
    proot_bin: PathBuf,
    lib_talloc: PathBuf,
    pub(super) rootfs_dir: PathBuf,
    pub(super) workspace_dir: PathBuf,
    pub(super) skills_dir: PathBuf,
    native_library_dir: PathBuf,
}

impl LinuxEnvPaths {
    pub(super) fn new(files_dir: &str, native_library_dir: &str) -> Self {
        let env_dir = Path::new(files_dir).join("linux-env");
        Self {
            proot_bin: Path::new(native_library_dir).join("libproot.so"),
            lib_talloc: env_dir.join("libtalloc.so.2"),
            rootfs_dir: env_dir.join("rootfs"),
            workspace_dir: env_dir.join("workspace"),
            skills_dir: Path::new(files_dir).join("prompt_skills"),
            native_library_dir: PathBuf::from(native_library_dir),
            env_dir,
        }
    }

    fn proot_path_file(&self) -> PathBuf {
        self.env_dir.join("proot_path")
    }

    fn version_file(&self) -> PathBuf {
        self.rootfs_dir.join(".version")
    }
}

pub fn is_ready(files_dir: &str, native_library_dir: &str) -> bool {
    let paths = LinuxEnvPaths::new(files_dir, native_library_dir);
    if paths.env_dir.exists() {
        let _ = fs::write(
            paths.proot_path_file(),
            paths.proot_bin.to_string_lossy().as_ref(),
        );
    }

    paths.proot_bin.exists()
        && paths.lib_talloc.exists()
        && is_version_current(&paths)
        && rootfs_essentials_exist(&paths)
}

pub fn setup(
    files_dir: &str,
    native_library_dir: &str,
    lib_talloc_bytes: &[u8],
    rootfs_gz_bytes: &[u8],
) -> anyhow::Result<()> {
    let paths = LinuxEnvPaths::new(files_dir, native_library_dir);
    fs::create_dir_all(&paths.env_dir)?;
    fs::write(
        paths.proot_path_file(),
        paths.proot_bin.to_string_lossy().as_ref(),
    )?;

    if !paths.lib_talloc.exists() {
        fs::write(&paths.lib_talloc, lib_talloc_bytes)?;
    }

    if !is_rootfs_current_and_complete(&paths) {
        if paths.rootfs_dir.exists() {
            fs::remove_dir_all(&paths.rootfs_dir).map_err(|e| {
                anyhow::anyhow!(
                    "failed to remove old rootfs {}: {}",
                    paths.rootfs_dir.display(),
                    e
                )
            })?;
        }
        fs::create_dir_all(&paths.rootfs_dir)?;
        extract_rootfs(rootfs_gz_bytes, &paths.rootfs_dir)?;
        write_version_marker(&paths)?;
    }

    configure_dns(&paths.rootfs_dir)?;
    configure_apk_mirror(&paths.rootfs_dir)?;
    fs::create_dir_all(&paths.workspace_dir)?;
    fs::create_dir_all(&paths.skills_dir)?;
    Ok(())
}

pub fn install_package(
    files_dir: &str,
    native_library_dir: &str,
    package: &str,
) -> anyhow::Result<String> {
    if !is_ready(files_dir, native_library_dir) {
        anyhow::bail!("Linux environment not ready");
    }
    let paths = LinuxEnvPaths::new(files_dir, native_library_dir);
    run_proot(
        &paths,
        "/root",
        &["/sbin/apk", "add", "--no-cache", package],
    )
}

pub fn execute_shell(
    files_dir: &str,
    native_library_dir: &str,
    command: &str,
    workdir: Option<&str>,
    timeout_secs: u64,
) -> anyhow::Result<String> {
    execute_shell_in_workspace(
        files_dir,
        native_library_dir,
        files_dir,
        command,
        workdir,
        timeout_secs,
        None,
    )
}

pub fn execute_shell_in_workspace(
    files_dir: &str,
    native_library_dir: &str,
    workspace_files_dir: &str,
    command: &str,
    workdir: Option<&str>,
    timeout_secs: u64,
    cancel: Option<&AtomicBool>,
) -> anyhow::Result<String> {
    if !is_ready(files_dir, native_library_dir) {
        anyhow::bail!("Linux environment not ready");
    }
    let mut paths = LinuxEnvPaths::new(files_dir, native_library_dir);
    paths.workspace_dir = workspace_mount_dir(workspace_files_dir);
    fs::create_dir_all(&paths.workspace_dir)?;
    fs::create_dir_all(&paths.skills_dir)?;
    run_proot_with_timeout(
        &paths,
        normalize_workdir(workdir),
        &["/bin/sh", "-lc", command],
        Some(Duration::from_secs(timeout_secs.clamp(1, 600))),
        cancel,
    )
}

pub struct LinuxCommandOutput {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

pub fn execute_program_in_workspace_dir(
    files_dir: &str,
    native_library_dir: &str,
    workspace_dir: &str,
    argv: &[String],
    workdir: Option<&str>,
    timeout_secs: u64,
    cancel: Option<&AtomicBool>,
) -> anyhow::Result<LinuxCommandOutput> {
    if argv.is_empty() {
        anyhow::bail!("argv is required");
    }
    if !is_ready(files_dir, native_library_dir) {
        anyhow::bail!("Linux environment not ready");
    }
    let mut paths = LinuxEnvPaths::new(files_dir, native_library_dir);
    paths.workspace_dir = PathBuf::from(workspace_dir);
    fs::create_dir_all(&paths.workspace_dir)?;
    fs::create_dir_all(&paths.skills_dir)?;
    let tail_args: Vec<&str> = argv.iter().map(String::as_str).collect();
    let output = run_proot_capture_with_timeout(
        &paths,
        normalize_workdir(workdir),
        &tail_args,
        Duration::from_secs(timeout_secs.clamp(1, 600)),
        cancel,
    )?;
    Ok(LinuxCommandOutput {
        exit_code: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

fn workspace_mount_dir(workspace_files_dir: &str) -> PathBuf {
    crate::storage::FileBridge::new(workspace_files_dir)
        .workspace_dir()
        .to_path_buf()
}

fn link_exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

fn rootfs_essentials_exist(paths: &LinuxEnvPaths) -> bool {
    link_exists(&paths.rootfs_dir.join("bin/sh")) && link_exists(&paths.rootfs_dir.join("sbin/apk"))
}

fn is_rootfs_current_and_complete(paths: &LinuxEnvPaths) -> bool {
    rootfs_essentials_exist(paths) && is_version_current(paths)
}

fn is_version_current(paths: &LinuxEnvPaths) -> bool {
    let Ok(version) = fs::read_to_string(paths.version_file()) else {
        return false;
    };
    version
        .trim()
        .parse::<i32>()
        .map(|version| version >= ROOTFS_VERSION)
        .unwrap_or(false)
}

fn write_version_marker(paths: &LinuxEnvPaths) -> anyhow::Result<()> {
    fs::write(paths.version_file(), ROOTFS_VERSION.to_string())?;
    Ok(())
}

fn extract_rootfs(rootfs_gz_bytes: &[u8], target_dir: &Path) -> anyhow::Result<()> {
    let decoder = GzDecoder::new(Cursor::new(rootfs_gz_bytes));
    let mut archive = Archive::new(decoder);
    extract_tar_compat(&mut archive, target_dir)?;
    Ok(())
}

fn extract_tar_compat<R: std::io::Read>(
    archive: &mut Archive<R>,
    target_dir: &Path,
) -> anyhow::Result<()> {
    for entry_result in archive.entries()? {
        let mut entry = entry_result?;
        let path = entry.path()?;
        let out_path = target_dir.join(path.as_ref());

        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let header = entry.header();
        match header.entry_type() {
            tar::EntryType::Directory => {
                fs::create_dir_all(&out_path).map_err(|e| {
                    anyhow::anyhow!("failed to create directory {}: {}", out_path.display(), e)
                })?;
            }
            tar::EntryType::Symlink => {
                let Some(link_name) = entry.link_name()? else {
                    continue;
                };
                let _ = fs::remove_file(&out_path);
                #[cfg(unix)]
                {
                    if let Err(err) = unix_fs::symlink(link_name.as_ref(), &out_path) {
                        log::warn!(
                            "android_linux_env: failed to create symlink {} -> {}: {}",
                            out_path.display(),
                            link_name.as_ref().display(),
                            err
                        );
                        // Fallback for Android filesystems that reject symlink creation:
                        // materialize symlink as a regular file copy when target exists.
                        if let Some(link_target) =
                            resolve_link_target_for_copy(target_dir, &out_path, link_name.as_ref())
                            && link_target.exists()
                        {
                            let _ = fs::copy(&link_target, &out_path);
                        }
                    }
                }
            }
            tar::EntryType::Link => {
                let Some(link_name) = entry.link_name()? else {
                    continue;
                };
                let link_target = target_dir.join(link_name.as_ref());
                if link_target.exists() {
                    fs::copy(&link_target, &out_path).map_err(|e| {
                        anyhow::anyhow!(
                            "failed to materialize hardlink {} -> {}: {}",
                            out_path.display(),
                            link_target.display(),
                            e
                        )
                    })?;
                } else {
                    log::warn!(
                        "android_linux_env: skip hardlink {} -> {} (target missing)",
                        out_path.display(),
                        link_target.display()
                    );
                }
            }
            tar::EntryType::Regular | tar::EntryType::Continuous => {
                entry.unpack(&out_path).map_err(|e| {
                    anyhow::anyhow!(
                        "failed to unpack regular file {}: {}",
                        out_path.display(),
                        e
                    )
                })?;
            }
            other => {
                log::warn!(
                    "android_linux_env: skip unsupported tar entry type {:?} for {}",
                    other,
                    out_path.display()
                );
            }
        }
    }
    Ok(())
}

fn configure_dns(rootfs_dir: &Path) -> anyhow::Result<()> {
    let resolv_conf = rootfs_dir.join("etc/resolv.conf");
    if let Some(parent) = resolv_conf.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(resolv_conf, "nameserver 8.8.8.8\nnameserver 8.8.4.4\n")?;
    Ok(())
}

fn configure_apk_mirror(rootfs_dir: &Path) -> anyhow::Result<()> {
    let repositories = rootfs_dir.join("etc/apk/repositories");
    if let Some(parent) = repositories.parent() {
        fs::create_dir_all(parent)?;
    }

    let alpine_branch = alpine_branch(rootfs_dir).unwrap_or_else(|| "latest-stable".to_string());
    fs::write(
        repositories,
        format!(
            "https://mirrors.aliyun.com/alpine/{alpine_branch}/main\n\
             https://mirrors.aliyun.com/alpine/{alpine_branch}/community\n"
        ),
    )?;
    Ok(())
}

fn alpine_branch(rootfs_dir: &Path) -> Option<String> {
    let release = fs::read_to_string(rootfs_dir.join("etc/alpine-release")).ok()?;
    let mut parts = release.trim().split('.');
    let major = parts.next()?;
    let minor = parts.next()?;
    Some(format!("v{major}.{minor}"))
}

fn resolve_link_target_for_copy(
    target_dir: &Path,
    out_path: &Path,
    link_name: &Path,
) -> Option<PathBuf> {
    let target_str = link_name.to_string_lossy();
    if target_str.starts_with("rootfs/") {
        return Some(target_dir.join(link_name));
    }

    if link_name.is_absolute() {
        let rel = link_name.strip_prefix("/").ok()?;
        return Some(target_dir.join("rootfs").join(rel));
    }

    out_path.parent().map(|parent| parent.join(link_name))
}

fn run_proot(paths: &LinuxEnvPaths, workdir: &str, tail_args: &[&str]) -> anyhow::Result<String> {
    run_proot_with_timeout(paths, workdir, tail_args, None, None)
}

fn run_proot_with_timeout(
    paths: &LinuxEnvPaths,
    workdir: &str,
    tail_args: &[&str],
    timeout: Option<Duration>,
    cancel: Option<&AtomicBool>,
) -> anyhow::Result<String> {
    let output = match timeout {
        Some(timeout) => {
            run_proot_capture_with_timeout(paths, workdir, tail_args, timeout, cancel)?
        }
        None => {
            let mut command = build_proot_command(paths, workdir, tail_args);
            configure_child_process(&mut command);
            command.output()?
        }
    };
    output_to_text_result(output)
}

fn run_proot_capture_with_timeout(
    paths: &LinuxEnvPaths,
    workdir: &str,
    tail_args: &[&str],
    timeout: Duration,
    cancel: Option<&AtomicBool>,
) -> anyhow::Result<Output> {
    output_with_timeout(
        build_proot_command(paths, workdir, tail_args),
        timeout,
        cancel,
    )
}

pub(super) fn build_proot_command(
    paths: &LinuxEnvPaths,
    workdir: &str,
    tail_args: &[&str],
) -> Command {
    let mut command = Command::new(&paths.proot_bin);

    let ldmusl = paths.native_library_dir.join("libldmusl.so");
    if ldmusl.exists() {
        command
            .arg("-b")
            .arg(format!("{}:/lib/ld-musl-aarch64.so.1", ldmusl.display()));
    }

    command
        .arg("-r")
        .arg(&paths.rootfs_dir)
        .arg("-b")
        .arg(format!("{}:/workspace", paths.workspace_dir.display()))
        .arg("-b")
        .arg(format!("{}:/skills", paths.skills_dir.display()))
        .arg("-w")
        .arg(workdir);
    add_standard_proot_binds(&mut command);
    for arg in tail_args {
        command.arg(arg);
    }

    command.env_clear();
    command.env("HOME", "/root");
    command.env(
        "PATH",
        "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    );
    // Terminal identity for interactive/TUI programs (claude code, codex, vim, …).
    // `env_clear()` strips the host env, so without these the child sees an empty
    // TERM and every TUI degrades to a non-interactive dumb terminal — no colors,
    // no alt-screen, no cursor control. `xterm-256color` matches both the xterm
    // widget's VT rendering capability and the terminfo entry shipped in the
    // Alpine rootfs at /etc/terminfo/x/xterm-256color. TERMINFO pins the search
    // path explicitly so ncurses always finds it even under proot re-rooting.
    command.env("TERM", "xterm-256color");
    command.env("COLORTERM", "truecolor");
    command.env("LANG", "C.UTF-8");
    command.env("TERMINFO", "/usr/share/terminfo");
    command.env("LD_LIBRARY_PATH", paths.env_dir.to_string_lossy().as_ref());
    let tmp_dir = paths.env_dir.join("tmp");
    let _ = fs::create_dir_all(&tmp_dir);
    command.env("PROOT_TMP_DIR", tmp_dir.to_string_lossy().as_ref());
    let loader = paths.native_library_dir.join("libloader.so");
    if loader.exists() {
        command.env("PROOT_LOADER", loader.to_string_lossy().as_ref());
    }
    command
}

fn add_standard_proot_binds(command: &mut Command) {
    for (host_path, guest_path) in STANDARD_PROOT_BINDS {
        add_existing_host_bind(command, Path::new(host_path), guest_path);
    }
}

fn add_existing_host_bind(command: &mut Command, host_path: &Path, guest_path: &str) {
    if host_path.exists() {
        command
            .arg("-b")
            .arg(format!("{}:{guest_path}", host_path.display()));
    }
}

fn output_to_text_result(output: Output) -> anyhow::Result<String> {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let text = if stderr.is_empty() {
        stdout.to_string()
    } else if stdout.is_empty() {
        stderr.to_string()
    } else {
        format!("{stdout}\n\n--- stderr ---\n{stderr}")
    };

    if output.status.success() {
        Ok(text)
    } else {
        anyhow::bail!(
            "proot command failed (exit={}): {}",
            output.status.code().unwrap_or(-1),
            text
        )
    }
}

pub(super) fn normalize_workdir(workdir: Option<&str>) -> &str {
    match workdir.map(str::trim).filter(|value| !value.is_empty()) {
        Some(value) => value,
        None => "/workspace",
    }
}

fn output_with_timeout(
    mut command: Command,
    timeout: Duration,
    cancel: Option<&AtomicBool>,
) -> anyhow::Result<Output> {
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    configure_child_process(&mut command);
    let mut child = command.spawn()?;
    let mut readers = OutputReaders::from_child(&mut child);
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            return collect_finished_output(&mut child, &mut readers, status);
        }
        if cancel
            .map(|flag| flag.load(Ordering::Relaxed))
            .unwrap_or(false)
        {
            terminate_child_tree(&mut child, &mut readers);
            anyhow::bail!("proot command cancelled by user");
        }
        if start.elapsed() >= timeout {
            terminate_child_tree(&mut child, &mut readers);
            let (stdout, stderr) = readers.snapshot();
            let stdout = String::from_utf8_lossy(&stdout);
            let stderr = String::from_utf8_lossy(&stderr);
            anyhow::bail!(
                "proot command timed out after {}s: {}{}{}",
                timeout.as_secs(),
                stdout,
                if stdout.is_empty() || stderr.is_empty() {
                    ""
                } else {
                    "\n\n--- stderr ---\n"
                },
                stderr
            );
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

pub(super) fn configure_child_process(command: &mut Command) {
    #[cfg(unix)]
    {
        command.process_group(0);
    }
}

fn collect_finished_output(
    child: &mut Child,
    readers: &mut OutputReaders,
    status: ExitStatus,
) -> anyhow::Result<Output> {
    readers.wait_until_finished(Duration::from_millis(200));
    if !readers.all_finished() {
        terminate_process_group(child, SIGTERM);
        readers.wait_until_finished(PROCESS_EXIT_GRACE);
    }
    if !readers.all_finished() {
        terminate_process_group(child, SIGKILL);
        readers.wait_until_finished(PROCESS_EXIT_GRACE);
    }
    let (stdout, stderr) = readers.snapshot();
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

fn terminate_child_tree(child: &mut Child, readers: &mut OutputReaders) {
    terminate_process_group(child, SIGTERM);
    if wait_for_child_exit(child, PROCESS_EXIT_GRACE).is_none() {
        terminate_process_group(child, SIGKILL);
        let _ = child.kill();
        let _ = wait_for_child_exit(child, PROCESS_EXIT_GRACE);
    }
    readers.wait_until_finished(PROCESS_EXIT_GRACE);
}

pub(super) fn wait_for_child_exit(child: &mut Child, grace: Duration) -> Option<ExitStatus> {
    let deadline = Instant::now() + grace;
    loop {
        if let Ok(Some(status)) = child.try_wait() {
            return Some(status);
        }
        if Instant::now() >= deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

#[cfg(unix)]
pub(super) fn terminate_process_group(child: &Child, signal: i32) {
    let pgid = child.id() as i32;
    if pgid > 0 {
        // SAFETY: `kill` is a libc syscall that is always safe to call — it
        // takes plain integers and returns a status code, with no pointer or
        // memory-safety contract. `-pgid` targets the child's process group
        // (guarded by `pgid > 0`); an invalid pgid simply yields an error we
        // intentionally ignore.
        unsafe {
            let _ = kill(-pgid, signal);
        }
    }
}

#[cfg(not(unix))]
pub(super) fn terminate_process_group(child: &mut Child, _signal: i32) {
    let _ = child.kill();
}

struct OutputReaders {
    stdout: Arc<Mutex<Vec<u8>>>,
    stderr: Arc<Mutex<Vec<u8>>>,
    stdout_handle: Option<JoinHandle<()>>,
    stderr_handle: Option<JoinHandle<()>>,
}

impl OutputReaders {
    fn from_child(child: &mut Child) -> Self {
        let stdout = Arc::new(Mutex::new(Vec::new()));
        let stderr = Arc::new(Mutex::new(Vec::new()));
        let stdout_handle = child
            .stdout
            .take()
            .map(|pipe| spawn_reader(pipe, stdout.clone()));
        let stderr_handle = child
            .stderr
            .take()
            .map(|pipe| spawn_reader(pipe, stderr.clone()));
        Self {
            stdout,
            stderr,
            stdout_handle,
            stderr_handle,
        }
    }

    fn all_finished(&self) -> bool {
        self.stdout_handle
            .as_ref()
            .map(JoinHandle::is_finished)
            .unwrap_or(true)
            && self
                .stderr_handle
                .as_ref()
                .map(JoinHandle::is_finished)
                .unwrap_or(true)
    }

    fn wait_until_finished(&mut self, grace: Duration) {
        let deadline = Instant::now() + grace;
        while !self.all_finished() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(25));
        }
        self.join_finished();
    }

    fn join_finished(&mut self) {
        if self
            .stdout_handle
            .as_ref()
            .map(JoinHandle::is_finished)
            .unwrap_or(false)
            && let Some(handle) = self.stdout_handle.take()
        {
            let _ = handle.join();
        }
        if self
            .stderr_handle
            .as_ref()
            .map(JoinHandle::is_finished)
            .unwrap_or(false)
            && let Some(handle) = self.stderr_handle.take()
        {
            let _ = handle.join();
        }
    }

    fn snapshot(&self) -> (Vec<u8>, Vec<u8>) {
        let stdout = self
            .stdout
            .lock()
            .map(|value| value.clone())
            .unwrap_or_default();
        let stderr = self
            .stderr
            .lock()
            .map(|value| value.clone())
            .unwrap_or_default();
        (stdout, stderr)
    }
}

fn spawn_reader<R>(mut pipe: R, output: Arc<Mutex<Vec<u8>>>) -> JoinHandle<()>
where
    R: Read + Send + 'static,
{
    thread::spawn(move || {
        let mut buffer = [0; 8192];
        loop {
            match pipe.read(&mut buffer) {
                Ok(0) => break,
                Ok(read) => {
                    if let Ok(mut output) = output.lock() {
                        output.extend_from_slice(&buffer[..read]);
                    } else {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;

    #[test]
    fn workspace_mount_dir_uses_selected_workspace_scope() {
        let temp_dir = tempfile::tempdir().unwrap();
        let scoped_files_dir = temp_dir
            .path()
            .join("napaxi_scopes")
            .join("accounts")
            .join("user")
            .join("agents")
            .join("napaxi");

        assert_eq!(
            workspace_mount_dir(scoped_files_dir.to_str().unwrap()),
            scoped_files_dir.join("linux-env").join("workspace")
        );
    }

    #[test]
    fn standard_proot_binds_cover_android_system_views() {
        assert!(STANDARD_PROOT_BINDS.contains(&("/proc", "/proc")));
        assert!(STANDARD_PROOT_BINDS.contains(&("/dev", "/dev")));
        assert!(STANDARD_PROOT_BINDS.contains(&("/sys", "/sys")));
    }

    #[cfg(unix)]
    #[test]
    fn output_with_timeout_kills_child_when_cancel_flips() {
        let cancel = Arc::new(AtomicBool::new(false));
        let cancel_for_thread = cancel.clone();
        thread::spawn(move || {
            thread::sleep(Duration::from_millis(150));
            cancel_for_thread.store(true, Ordering::Relaxed);
        });

        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg("sleep 30");
        let started = Instant::now();
        let result = output_with_timeout(command, Duration::from_secs(30), Some(&cancel));
        let elapsed = started.elapsed();

        let err = result.expect_err("cancel must surface as an error");
        assert!(
            err.to_string().contains("cancelled"),
            "error must mention cancellation: {err}"
        );
        assert!(
            elapsed < Duration::from_secs(2),
            "cancelled child must exit promptly, elapsed={:?}",
            elapsed
        );
    }

    #[cfg(unix)]
    #[test]
    fn output_with_timeout_returns_when_descendant_keeps_stdout_open() {
        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg("(sleep 30) & echo parent-done");
        let started = Instant::now();
        let output = output_with_timeout(command, Duration::from_secs(30), None)
            .expect("parent shell should complete");
        let elapsed = started.elapsed();

        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(
            stdout.contains("parent-done"),
            "stdout should include parent output: {stdout:?}"
        );
        assert!(
            elapsed < Duration::from_secs(3),
            "output collection must not wait for background descendants, elapsed={:?}",
            elapsed
        );
    }

    #[cfg(unix)]
    #[test]
    fn output_with_timeout_returns_promptly_after_timeout() {
        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg("trap '' TERM; sleep 30");
        let started = Instant::now();
        let result = output_with_timeout(command, Duration::from_millis(100), None);
        let elapsed = started.elapsed();

        let err = result.expect_err("timeout must surface as an error");
        assert!(
            err.to_string().contains("timed out"),
            "error must mention timeout: {err}"
        );
        assert!(
            elapsed < Duration::from_secs(4),
            "timeout cleanup must be bounded, elapsed={:?}",
            elapsed
        );
    }
}
