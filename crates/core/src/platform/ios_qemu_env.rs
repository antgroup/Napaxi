//! iOS QEMU sandbox backend.
//!
//! This module deliberately does **not** depend on the adjacent sandbox SDK Swift
//! or UniFFI layer. Napaxi owns rootfs preparation and calls the vendored lower
//! level QEMU C bridge directly when the iOS app links those objects/static
//! libraries.

use std::ffi::{CStr, CString, c_char, c_int};
use std::fs::{self, File};
use std::io::Read;
#[cfg(unix)]
use std::os::unix::fs as unix_fs;
use std::path::{Component, Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use flate2::read::GzDecoder;
use tar::Archive;

const ROOTFS_VERSION: i32 = 3;
const STDOUT_SIZE: usize = 1024 * 1024;
const STDERR_SIZE: usize = 256 * 1024;

const META_XATTR_NAME: &[u8] = b"com.mobilesandbox.meta\0";
const META_RECORD_VERSION: u32 = 1;
const META_TYPE_REG: u32 = 1;
const META_TYPE_DIR: u32 = 2;
const META_TYPE_SYMLINK: u32 = 3;
const META_TYPE_CHR: u32 = 4;
const META_TYPE_BLK: u32 = 5;
const META_TYPE_FIFO: u32 = 6;

unsafe extern "C" {
    fn qemu_sandbox_init(rootfs_path: *const c_char, mount_table: *const c_char) -> c_int;
    fn qemu_sandbox_exec_with_id(
        elf_path: *const c_char,
        argv_json: *const c_char,
        env_json: *const c_char,
        working_dir: *const c_char,
        command_id: u64,
        has_command_id: c_int,
        stdout_buf: *mut c_char,
        stdout_size: usize,
        stderr_buf: *mut c_char,
        stderr_size: usize,
    ) -> c_int;
    fn qemu_cancel(command_id: u64) -> c_int;
    fn qemu_session_open(
        command: *const c_char,
        working_dir: *const c_char,
        env_json: *const c_char,
        session_id: u64,
        cols: c_int,
        rows: c_int,
    ) -> c_int;
    fn qemu_session_write(session_id: u64, data: *const c_char) -> c_int;
    #[allow(dead_code)]
    fn qemu_session_resize(session_id: u64, cols: c_int, rows: c_int) -> c_int;
    fn qemu_session_read(session_id: u64, output_buf: *mut c_char, output_buf_size: usize)
    -> c_int;
    fn qemu_session_wait_output(session_id: u64) -> c_int;
    fn qemu_session_close(session_id: u64) -> c_int;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IosQemuCommandResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct IosQemuPaths {
    env_dir: PathBuf,
    rootfs_dir: PathBuf,
    workspace_dir: PathBuf,
    skills_dir: PathBuf,
}

impl IosQemuPaths {
    #[allow(dead_code)]
    fn new(files_dir: &str, workspace_files_dir: &str) -> Self {
        Self::with_workspace_dir(files_dir, workspace_mount_dir(workspace_files_dir))
    }

    fn with_workspace_dir(files_dir: &str, workspace_dir: PathBuf) -> Self {
        let env_dir = Path::new(files_dir).join("linux-env");
        Self {
            rootfs_dir: env_dir.join("rootfs"),
            workspace_dir,
            skills_dir: Path::new(files_dir).join("prompt_skills"),
            env_dir,
        }
    }

    fn version_file(&self) -> PathBuf {
        self.rootfs_dir.join(".version")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct InitState {
    rootfs_dir: PathBuf,
    mount_table: String,
}

fn rootfs_archive_path_cell() -> &'static Mutex<Option<String>> {
    static ROOTFS_ARCHIVE_PATH: OnceLock<Mutex<Option<String>>> = OnceLock::new();
    ROOTFS_ARCHIVE_PATH.get_or_init(|| Mutex::new(None))
}

fn init_state_cell() -> &'static Mutex<Option<InitState>> {
    static INIT_STATE: OnceLock<Mutex<Option<InitState>>> = OnceLock::new();
    INIT_STATE.get_or_init(|| Mutex::new(None))
}

pub fn register_rootfs_archive_path(path: &str) {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return;
    }
    if let Ok(mut slot) = rootfs_archive_path_cell().lock() {
        *slot = Some(trimmed.to_string());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_ios_qemu_register_rootfs_archive_path(path: *const c_char) {
    if path.is_null() {
        return;
    }
    // SAFETY: `path` comes from the Swift/C adapter and is checked for null
    // above. Invalid UTF-8 is lossily converted because this is only a file path
    // registration convenience.
    let value = unsafe { CStr::from_ptr(path) }
        .to_string_lossy()
        .into_owned();
    register_rootfs_archive_path(&value);
}

pub fn is_ready(files_dir: &str) -> bool {
    ensure_setup_and_init(files_dir, files_dir).is_ok()
}

pub fn execute_in_workspace(
    files_dir: &str,
    workspace_files_dir: &str,
    command: &str,
    workdir: Option<&str>,
    timeout_ms: i32,
) -> IosQemuCommandResult {
    let paths = match ensure_setup_and_init(files_dir, workspace_files_dir) {
        Ok(paths) => paths,
        Err(error) => {
            return IosQemuCommandResult {
                exit_code: 127,
                stdout: String::new(),
                stderr: String::new(),
                error: Some(error.to_string()),
            };
        }
    };

    let shell_path = paths.rootfs_dir.join("bin/sh");
    let argv_json = match serde_json::to_string(&["-lc", command]) {
        Ok(value) => value,
        Err(error) => {
            return command_error(format!("failed to encode shell argv: {error}"));
        }
    };
    let env_json = qemu_env_json();
    let working_dir = normalize_workdir(workdir);
    let command_id = next_command_id();

    let shell_c = match path_cstring(&shell_path, "shell path") {
        Ok(value) => value,
        Err(error) => return command_error(error),
    };
    let argv_c = match CString::new(argv_json) {
        Ok(value) => value,
        Err(error) => return command_error(format!("invalid shell argv: {error}")),
    };
    let env_c = match CString::new(env_json) {
        Ok(value) => value,
        Err(error) => return command_error(format!("invalid shell env: {error}")),
    };
    let workdir_c = match CString::new(working_dir) {
        Ok(value) => value,
        Err(error) => return command_error(format!("invalid working directory: {error}")),
    };

    let mut stdout = vec![0 as c_char; STDOUT_SIZE];
    let mut stderr = vec![0 as c_char; STDERR_SIZE];
    let timeout = Duration::from_millis(timeout_ms.max(1000) as u64);
    let started = Instant::now();

    let exit_code = loop {
        // SAFETY: all pointers are valid NUL-terminated C strings for the
        // duration of the call; output buffers are allocated, writable, and
        // passed with their exact lengths. The linked QEMU bridge owns no Rust
        // references and writes C strings into the buffers.
        let code = unsafe {
            qemu_sandbox_exec_with_id(
                shell_c.as_ptr(),
                argv_c.as_ptr(),
                env_c.as_ptr(),
                workdir_c.as_ptr(),
                command_id,
                1,
                stdout.as_mut_ptr(),
                stdout.len(),
                stderr.as_mut_ptr(),
                stderr.len(),
            )
        };
        if started.elapsed() <= timeout {
            break code;
        }
        // The current C bridge is synchronous, so this branch is reached only
        // after return. Keep the cancel hook here for forward compatibility with
        // bridge implementations that observe cancellation between dispatches.
        // SAFETY: command_id was allocated by this process and registered with
        // qemu_sandbox_exec_with_id above.
        let _ = unsafe { qemu_cancel(command_id) };
        break -124;
    };

    // SAFETY: buffers were zero-initialized and the C bridge writes C strings.
    let stdout = unsafe { CStr::from_ptr(stdout.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    // SAFETY: buffers were zero-initialized and the C bridge writes C strings.
    let stderr = unsafe { CStr::from_ptr(stderr.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    let error = if exit_code < 0 || exit_code == 127 || exit_code == 124 {
        Some(if stderr.is_empty() {
            format!("iOS QEMU command failed with exit code {exit_code}")
        } else {
            stderr.clone()
        })
    } else {
        None
    };

    IosQemuCommandResult {
        exit_code,
        stdout,
        stderr,
        error,
    }
}

fn command_error(error: String) -> IosQemuCommandResult {
    IosQemuCommandResult {
        exit_code: 127,
        stdout: String::new(),
        stderr: error.clone(),
        error: Some(error),
    }
}

fn ensure_setup_and_init(
    files_dir: &str,
    workspace_files_dir: &str,
) -> anyhow::Result<IosQemuPaths> {
    ensure_setup_and_init_with_workspace_dir(files_dir, workspace_mount_dir(workspace_files_dir))
}

fn ensure_setup_and_init_with_workspace_dir(
    files_dir: &str,
    workspace_dir: PathBuf,
) -> anyhow::Result<IosQemuPaths> {
    let paths = IosQemuPaths::with_workspace_dir(files_dir, workspace_dir);
    setup_rootfs(&paths)?;
    fs::create_dir_all(&paths.workspace_dir)?;
    fs::create_dir_all(&paths.skills_dir)?;
    configure_dns(&paths.rootfs_dir)?;
    configure_apk_mirror(&paths.rootfs_dir)?;
    init_qemu(&paths)?;
    Ok(paths)
}

fn setup_rootfs(paths: &IosQemuPaths) -> anyhow::Result<()> {
    fs::create_dir_all(&paths.env_dir)?;
    if is_rootfs_current_and_complete(paths) {
        return Ok(());
    }

    let archive_path = rootfs_archive_path_cell()
        .lock()
        .ok()
        .and_then(|slot| slot.clone())
        .ok_or_else(|| anyhow::anyhow!("iOS QEMU rootfs archive has not been registered"))?;
    if !Path::new(&archive_path).is_file() {
        anyhow::bail!("iOS QEMU rootfs archive not found at {archive_path}");
    }

    if paths.rootfs_dir.exists() {
        fs::remove_dir_all(&paths.rootfs_dir).map_err(|error| {
            anyhow::anyhow!(
                "failed to remove old iOS QEMU rootfs {}: {error}",
                paths.rootfs_dir.display()
            )
        })?;
    }
    fs::create_dir_all(&paths.rootfs_dir)?;
    extract_rootfs_archive(&archive_path, &paths.rootfs_dir)?;
    rewrite_absolute_symlinks(&paths.rootfs_dir)?;
    fs::write(paths.version_file(), ROOTFS_VERSION.to_string())?;
    Ok(())
}

fn init_qemu(paths: &IosQemuPaths) -> anyhow::Result<()> {
    let mount_table = mount_table(paths);
    let next_state = InitState {
        rootfs_dir: paths.rootfs_dir.clone(),
        mount_table: mount_table.clone(),
    };
    if init_state_cell()
        .lock()
        .ok()
        .and_then(|slot| slot.clone())
        .as_ref()
        == Some(&next_state)
    {
        return Ok(());
    }

    let rootfs_c = path_cstring(&paths.rootfs_dir, "rootfs path").map_err(anyhow::Error::msg)?;
    let mount_table_c = CString::new(mount_table.as_str())?;
    // SAFETY: rootfs and mount table are valid C strings. The QEMU bridge copies
    // both into process-global storage during initialization.
    let rc = unsafe { qemu_sandbox_init(rootfs_c.as_ptr(), mount_table_c.as_ptr()) };
    if rc != 0 {
        anyhow::bail!("QEMU init failed with code {rc}");
    }
    if let Ok(mut slot) = init_state_cell().lock() {
        *slot = Some(next_state);
    }
    Ok(())
}

fn workspace_mount_dir(workspace_files_dir: &str) -> PathBuf {
    crate::storage::FileBridge::new(workspace_files_dir)
        .workspace_dir()
        .to_path_buf()
}

fn is_rootfs_current_and_complete(paths: &IosQemuPaths) -> bool {
    rootfs_essentials_exist(paths) && is_version_current(paths)
}

fn rootfs_essentials_exist(paths: &IosQemuPaths) -> bool {
    link_exists(&paths.rootfs_dir.join("bin/sh")) && link_exists(&paths.rootfs_dir.join("sbin/apk"))
}

fn link_exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

fn is_version_current(paths: &IosQemuPaths) -> bool {
    let Ok(version) = fs::read_to_string(paths.version_file()) else {
        return false;
    };
    version
        .trim()
        .parse::<i32>()
        .map(|version| version >= ROOTFS_VERSION)
        .unwrap_or(false)
}

fn extract_rootfs_archive(archive_path: &str, target_dir: &Path) -> anyhow::Result<()> {
    let archive = File::open(archive_path)?;
    let decoder = GzDecoder::new(archive);
    let mut archive = Archive::new(decoder);
    for entry in archive.entries()? {
        let mut entry = entry?;
        unpack_rootfs_entry(&mut entry, target_dir)?;
    }
    Ok(())
}

fn unpack_rootfs_entry<R: Read>(
    entry: &mut tar::Entry<R>,
    rootfs_path: &Path,
) -> anyhow::Result<()> {
    let entry_type = entry.header().entry_type();
    let uid = entry.header().uid().unwrap_or(0) as u32;
    let gid = entry.header().gid().unwrap_or(0) as u32;
    let mode = entry.header().mode().unwrap_or(0) as u32 & 0o7777;
    let entry_path = entry.path()?.into_owned();

    if entry_type == tar::EntryType::Directory {
        let Some(dest) = rootfs_dest_path(rootfs_path, &entry_path) else {
            return Ok(());
        };
        ensure_parent_inside_rootfs(rootfs_path, &dest)?;
        fs::create_dir_all(&dest)?;
        set_host_dir_writable(&dest)?;
        if uid == 0 && gid == 0 && mode == 0o755 {
            return Ok(());
        }
        return write_meta_xattr(&dest, META_TYPE_DIR, mode, uid, gid, 0, None, false);
    }

    if matches!(
        entry_type,
        tar::EntryType::Char | tar::EntryType::Block | tar::EntryType::Fifo
    ) {
        let Some(dest) = rootfs_dest_path(rootfs_path, &entry_path) else {
            return Ok(());
        };
        ensure_parent_inside_rootfs(rootfs_path, &dest)?;
        let (file_type, rdev) = match entry_type {
            tar::EntryType::Char | tar::EntryType::Block => {
                let major = entry.header().device_major().ok().flatten().unwrap_or(0);
                let minor = entry.header().device_minor().ok().flatten().unwrap_or(0);
                let file_type = if entry_type == tar::EntryType::Char {
                    META_TYPE_CHR
                } else {
                    META_TYPE_BLK
                };
                (file_type, linux_makedev(u64::from(major), u64::from(minor)))
            }
            _ => (META_TYPE_FIFO, 0),
        };
        create_special_placeholder(&dest, entry_type)?;
        return write_meta_xattr(&dest, file_type, mode, uid, gid, rdev, None, false);
    }

    let symlink_target = if entry_type == tar::EntryType::Symlink {
        match entry.link_name_bytes() {
            Some(bytes) if bytes.first() == Some(&b'/') => Some(bytes.into_owned()),
            _ => None,
        }
    } else {
        None
    };

    let unpacked = entry.unpack_in(rootfs_path)?;
    if !unpacked {
        return Ok(());
    }
    let Some(file_type) = meta_type_for_entry(entry_type) else {
        return Ok(());
    };
    if uid == 0 && gid == 0 && (mode & 0o7000) == 0 && symlink_target.is_none() {
        return Ok(());
    }
    let Some(dest) = rootfs_dest_path(rootfs_path, &entry_path) else {
        return Ok(());
    };
    write_meta_xattr(
        &dest,
        file_type,
        mode,
        uid,
        gid,
        0,
        symlink_target.as_deref(),
        entry_type == tar::EntryType::Symlink,
    )
}

fn meta_type_for_entry(entry_type: tar::EntryType) -> Option<u32> {
    match entry_type {
        tar::EntryType::Regular | tar::EntryType::Continuous | tar::EntryType::GNUSparse => {
            Some(META_TYPE_REG)
        }
        tar::EntryType::Directory => Some(META_TYPE_DIR),
        tar::EntryType::Symlink => Some(META_TYPE_SYMLINK),
        tar::EntryType::Char => Some(META_TYPE_CHR),
        tar::EntryType::Block => Some(META_TYPE_BLK),
        tar::EntryType::Fifo => Some(META_TYPE_FIFO),
        _ => None,
    }
}

fn rootfs_dest_path(rootfs_path: &Path, entry_path: &Path) -> Option<PathBuf> {
    let mut dest = rootfs_path.to_path_buf();
    let mut has_component = false;
    for component in entry_path.components() {
        match component {
            Component::Normal(part) => {
                dest.push(part);
                has_component = true;
            }
            Component::CurDir => {}
            _ => return None,
        }
    }
    has_component.then_some(dest)
}

fn ensure_parent_inside_rootfs(rootfs_path: &Path, dest: &Path) -> anyhow::Result<()> {
    let Some(parent) = dest.parent() else {
        return Ok(());
    };
    fs::create_dir_all(parent)?;
    let real_root = fs::canonicalize(rootfs_path)?;
    let real_parent = fs::canonicalize(parent)?;
    if !real_parent.starts_with(real_root) {
        anyhow::bail!(
            "QEMU rootfs entry {} escapes rootfs via a symlinked parent directory",
            dest.display()
        );
    }
    Ok(())
}

#[cfg(unix)]
fn set_host_dir_writable(dest: &Path) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(dest, fs::Permissions::from_mode(0o755))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_host_dir_writable(_dest: &Path) -> anyhow::Result<()> {
    Ok(())
}

#[cfg(unix)]
fn create_special_placeholder(dest: &Path, entry_type: tar::EntryType) -> anyhow::Result<()> {
    use std::os::unix::ffi::OsStrExt;
    if entry_type == tar::EntryType::Fifo {
        let c_dest = CString::new(dest.as_os_str().as_bytes())?;
        // SAFETY: path is a valid C string and mode is a plain POSIX mode.
        let rc = unsafe { libc::mkfifo(c_dest.as_ptr(), 0o644) };
        if rc != 0 {
            anyhow::bail!(
                "failed to create QEMU rootfs FIFO {}: {}",
                dest.display(),
                std::io::Error::last_os_error()
            );
        }
        return Ok(());
    }
    use std::os::unix::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(dest)?;
    Ok(())
}

#[cfg(not(unix))]
fn create_special_placeholder(dest: &Path, _entry_type: tar::EntryType) -> anyhow::Result<()> {
    File::create(dest)?;
    Ok(())
}

fn linux_makedev(major: u64, minor: u64) -> u64 {
    ((major & 0xfff) << 8) | (minor & 0xff) | ((minor & !0xff) << 12)
}

fn encode_meta_record(
    file_type: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    rdev: u64,
    symlink_target: Option<&[u8]>,
) -> Vec<u8> {
    let target = symlink_target.unwrap_or(&[]);
    let mut record = Vec::with_capacity(32 + target.len());
    record.extend_from_slice(&META_RECORD_VERSION.to_le_bytes());
    record.extend_from_slice(&file_type.to_le_bytes());
    record.extend_from_slice(&(mode & 0o7777).to_le_bytes());
    record.extend_from_slice(&uid.to_le_bytes());
    record.extend_from_slice(&gid.to_le_bytes());
    record.extend_from_slice(&rdev.to_le_bytes());
    record.extend_from_slice(&(target.len() as u32).to_le_bytes());
    record.extend_from_slice(target);
    record
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn write_meta_xattr(
    dest: &Path,
    file_type: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    rdev: u64,
    symlink_target: Option<&[u8]>,
    nofollow: bool,
) -> anyhow::Result<()> {
    use std::os::unix::ffi::OsStrExt;
    let record = encode_meta_record(file_type, mode, uid, gid, rdev, symlink_target);
    let path = CString::new(dest.as_os_str().as_bytes())?;
    let options = if nofollow { libc::XATTR_NOFOLLOW } else { 0 };
    let set = || {
        // SAFETY: all pointers point to valid byte buffers for the duration of
        // the call; xattr name is NUL-terminated by construction.
        unsafe {
            libc::setxattr(
                path.as_ptr(),
                META_XATTR_NAME.as_ptr().cast(),
                record.as_ptr().cast(),
                record.len(),
                0,
                options,
            )
        }
    };
    let mut rc = set();
    if rc != 0 && !nofollow {
        let err = std::io::Error::last_os_error();
        if matches!(err.raw_os_error(), Some(libc::EACCES) | Some(libc::EPERM)) {
            use std::os::unix::fs::PermissionsExt;
            if let Ok(meta) = fs::metadata(dest) {
                let host_mode = meta.permissions().mode() & 0o7777;
                if host_mode & 0o200 == 0
                    && fs::set_permissions(dest, fs::Permissions::from_mode(host_mode | 0o200))
                        .is_ok()
                {
                    rc = set();
                    let _ = fs::set_permissions(dest, fs::Permissions::from_mode(host_mode));
                }
            }
        }
    }
    if rc != 0 {
        anyhow::bail!(
            "failed to write QEMU rootfs metadata xattr on {}: {}",
            dest.display(),
            std::io::Error::last_os_error()
        );
    }
    Ok(())
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn write_meta_xattr(
    _dest: &Path,
    _file_type: u32,
    _mode: u32,
    _uid: u32,
    _gid: u32,
    _rdev: u64,
    _symlink_target: Option<&[u8]>,
    _nofollow: bool,
) -> anyhow::Result<()> {
    Ok(())
}

fn rewrite_absolute_symlinks(rootfs_path: &Path) -> anyhow::Result<()> {
    for symlink in collect_symlinks(rootfs_path)? {
        let target = fs::read_link(&symlink)?;
        if !target.is_absolute() {
            continue;
        }
        let rootfs_target = rootfs_path.join(strip_absolute_prefix(&target));
        let parent = symlink.parent().unwrap_or(rootfs_path);
        let relative = relative_path(parent, &rootfs_target);
        let saved_record = read_meta_xattr_raw(&symlink);
        fs::remove_file(&symlink)?;
        create_symlink(&relative, &symlink)?;
        if let Some(record) = saved_record {
            write_meta_xattr_raw(&symlink, &record)?;
        }
    }
    Ok(())
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn read_meta_xattr_raw(link: &Path) -> Option<Vec<u8>> {
    use std::os::unix::ffi::OsStrExt;
    let path = CString::new(link.as_os_str().as_bytes()).ok()?;
    let mut buf = vec![0u8; 32 + 4096];
    // SAFETY: buffers are valid and xattr name is NUL-terminated by construction.
    let len = unsafe {
        libc::getxattr(
            path.as_ptr(),
            META_XATTR_NAME.as_ptr().cast(),
            buf.as_mut_ptr().cast(),
            buf.len(),
            0,
            libc::XATTR_NOFOLLOW,
        )
    };
    if len < 0 {
        return None;
    }
    buf.truncate(len as usize);
    Some(buf)
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn read_meta_xattr_raw(_link: &Path) -> Option<Vec<u8>> {
    None
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn write_meta_xattr_raw(link: &Path, record: &[u8]) -> anyhow::Result<()> {
    use std::os::unix::ffi::OsStrExt;
    let path = CString::new(link.as_os_str().as_bytes())?;
    // SAFETY: all pointers point to valid byte buffers for the duration of the
    // call; xattr name is NUL-terminated by construction.
    let rc = unsafe {
        libc::setxattr(
            path.as_ptr(),
            META_XATTR_NAME.as_ptr().cast(),
            record.as_ptr().cast(),
            record.len(),
            0,
            libc::XATTR_NOFOLLOW,
        )
    };
    if rc != 0 {
        anyhow::bail!(
            "failed to restore QEMU rootfs metadata xattr on {}: {}",
            link.display(),
            std::io::Error::last_os_error()
        );
    }
    Ok(())
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn write_meta_xattr_raw(_link: &Path, _record: &[u8]) -> anyhow::Result<()> {
    Ok(())
}

fn collect_symlinks(rootfs_path: &Path) -> anyhow::Result<Vec<PathBuf>> {
    let mut symlinks = Vec::new();
    collect_symlinks_in(rootfs_path, &mut symlinks)?;
    Ok(symlinks)
}

fn collect_symlinks_in(path: &Path, symlinks: &mut Vec<PathBuf>) -> anyhow::Result<()> {
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            symlinks.push(path);
        } else if metadata.is_dir() {
            collect_symlinks_in(&path, symlinks)?;
        }
    }
    Ok(())
}

fn strip_absolute_prefix(path: &Path) -> &Path {
    path.strip_prefix(Path::new("/")).unwrap_or(path)
}

fn relative_path(from_dir: &Path, to: &Path) -> PathBuf {
    let mut from_components = from_dir.components().collect::<Vec<_>>();
    let mut to_components = to.components().collect::<Vec<_>>();
    while !from_components.is_empty()
        && !to_components.is_empty()
        && from_components[0] == to_components[0]
    {
        from_components.remove(0);
        to_components.remove(0);
    }
    let mut relative = PathBuf::new();
    for _ in &from_components {
        relative.push("..");
    }
    for component in to_components {
        relative.push(component.as_os_str());
    }
    if relative.as_os_str().is_empty() {
        relative.push(".");
    }
    relative
}

#[cfg(unix)]
fn create_symlink(target: &Path, link: &Path) -> anyhow::Result<()> {
    unix_fs::symlink(target, link)?;
    Ok(())
}

#[cfg(not(unix))]
fn create_symlink(_target: &Path, link: &Path) -> anyhow::Result<()> {
    anyhow::bail!(
        "cannot rewrite QEMU rootfs symlink {} on this platform",
        link.display()
    )
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

fn mount_table(paths: &IosQemuPaths) -> String {
    [
        ("/workspace", paths.workspace_dir.as_path()),
        ("/skills", paths.skills_dir.as_path()),
    ]
    .into_iter()
    .map(|(guest, host)| {
        format!(
            "{}={}",
            percent_escape_mount_value(guest),
            percent_escape_mount_value(&host.to_string_lossy())
        )
    })
    .collect::<Vec<_>>()
    .join(";")
}

fn percent_escape_mount_value(value: &str) -> String {
    value
        .as_bytes()
        .iter()
        .flat_map(|byte| match *byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b'.' | b'_' | b'-' => {
                vec![*byte as char]
            }
            other => format!("%{other:02X}").chars().collect::<Vec<_>>(),
        })
        .collect()
}

fn normalize_workdir(workdir: Option<&str>) -> &'static str {
    let Some(workdir) = workdir else {
        return "/workspace";
    };
    if workdir.is_empty() || workdir == "/" || workdir == "/workspace" {
        return "/workspace";
    }
    if workdir.starts_with("/workspace/") {
        // The C bridge needs the path to exist. Napaxi shell calls usually pass
        // either /workspace or host-side paths; start conservative and use the
        // mounted workspace root for unsupported shapes.
        return "/workspace";
    }
    "/workspace"
}

#[path = "ios_qemu_env/pty.rs"]
pub mod pty;

fn qemu_env_json() -> String {
    serde_json::json!({
        "HOME": "/root",
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "TERM": "xterm-256color",
        "COLORTERM": "truecolor",
        "LANG": "C.UTF-8",
        "TERMINFO": "/usr/share/terminfo",
        "SHELL": "/bin/sh"
    })
    .to_string()
}

fn path_cstring(path: &Path, label: &str) -> Result<CString, String> {
    CString::new(path.to_string_lossy().as_bytes())
        .map_err(|error| format!("invalid {label}: {error}"))
}

fn next_command_id() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT_COMMAND_ID: AtomicU64 = AtomicU64::new(1);
    NEXT_COMMAND_ID.fetch_add(1, Ordering::Relaxed)
}
