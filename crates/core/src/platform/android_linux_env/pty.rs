use std::fs;
use std::io::{Read, Write};
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use super::{
    LinuxEnvPaths, PROCESS_EXIT_GRACE, SIGKILL, SIGTERM, build_proot_command, is_ready,
    normalize_workdir, terminate_process_group, wait_for_child_exit,
};

const PTY_EVENT_FLUSH: Duration = Duration::from_millis(20);

#[cfg(unix)]
use std::ffi::c_void;
#[cfg(unix)]
use std::fs::File;
#[cfg(unix)]
use std::os::fd::FromRawFd;

#[cfg(unix)]
const TIOCSWINSZ: u64 = 0x5414;
#[cfg(unix)]
const TIOCSCTTY: u64 = 0x540E;

#[cfg(unix)]
#[repr(C)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

#[cfg(unix)]
unsafe extern "C" {
    fn openpty(
        amaster: *mut i32,
        aslave: *mut i32,
        name: *mut i8,
        termp: *const c_void,
        winp: *const Winsize,
    ) -> i32;
    fn dup(fd: i32) -> i32;
    fn close(fd: i32) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn setsid() -> i32;
}

static NEXT_PTY_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static PTY_SESSIONS: OnceLock<Mutex<std::collections::HashMap<u64, PtySession>>> = OnceLock::new();

#[derive(Debug, Clone)]
pub enum PtyEventKind {
    Output,
    Exit,
    Closed,
    Log,
}

#[derive(Debug, Clone)]
pub struct PtyEvent {
    pub session_id: u64,
    pub kind: PtyEventKind,
    pub data: String,
    pub exit_code: Option<i32>,
}

enum PtyCommand {
    Write(String),
    Resize { cols: u16, rows: u16 },
    Close,
}

struct PtySession {
    tx: Sender<PtyCommand>,
    events: Arc<Mutex<Receiver<PtyEvent>>>,
    join: Option<JoinHandle<()>>,
}

pub fn open_pty_session(
    files_dir: &str,
    native_library_dir: &str,
    workspace_dir: &str,
    argv: &[String],
    workdir: Option<&str>,
    cols: u16,
    rows: u16,
) -> anyhow::Result<u64> {
    if argv.is_empty() {
        anyhow::bail!("argv is required");
    }
    if !is_ready(files_dir, native_library_dir) {
        anyhow::bail!("Linux environment not ready");
    }

    let session_id = NEXT_PTY_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let mut paths = LinuxEnvPaths::new(files_dir, native_library_dir);
    paths.workspace_dir = PathBuf::from(workspace_dir);
    fs::create_dir_all(&paths.workspace_dir)?;
    fs::create_dir_all(&paths.skills_dir)?;

    let (cmd_tx, cmd_rx) = mpsc::channel();
    let (event_tx, event_rx) = mpsc::channel();
    let tail_args: Vec<String> = argv.to_vec();
    let workdir = normalize_workdir(workdir).to_string();
    let join = thread::spawn(move || {
        if let Err(error) = run_pty_session(
            session_id,
            paths,
            workdir,
            tail_args,
            cols.max(1),
            rows.max(1),
            cmd_rx,
            event_tx.clone(),
        ) {
            let _ = event_tx.send(PtyEvent {
                session_id,
                kind: PtyEventKind::Log,
                data: error.to_string(),
                exit_code: None,
            });
            let _ = event_tx.send(PtyEvent {
                session_id,
                kind: PtyEventKind::Closed,
                data: String::new(),
                exit_code: None,
            });
        }
    });

    let session = PtySession {
        tx: cmd_tx,
        events: Arc::new(Mutex::new(event_rx)),
        join: Some(join),
    };
    pty_sessions()
        .lock()
        .map_err(|e| anyhow::anyhow!("PTY session registry lock poisoned: {}", e))?
        .insert(session_id, session);
    Ok(session_id)
}

pub fn write_pty_session(session_id: u64, data: &str) -> anyhow::Result<()> {
    send_pty_command(session_id, PtyCommand::Write(data.to_string()))
}

pub fn resize_pty_session(session_id: u64, cols: u16, rows: u16) -> anyhow::Result<()> {
    send_pty_command(
        session_id,
        PtyCommand::Resize {
            cols: cols.max(1),
            rows: rows.max(1),
        },
    )
}

pub fn close_pty_session(session_id: u64) -> anyhow::Result<()> {
    let mut session = pty_sessions()
        .lock()
        .map_err(|e| anyhow::anyhow!("PTY session registry lock poisoned: {}", e))?
        .remove(&session_id)
        .ok_or_else(|| anyhow::anyhow!("PTY session {session_id} not found"))?;
    let _ = session.tx.send(PtyCommand::Close);
    if let Some(join) = session.join.take() {
        let _ = join.join();
    }
    Ok(())
}

pub fn drain_pty_events(session_id: u64) -> anyhow::Result<Vec<PtyEvent>> {
    let events = {
        let sessions = pty_sessions()
            .lock()
            .map_err(|e| anyhow::anyhow!("PTY session registry lock poisoned: {}", e))?;
        sessions
            .get(&session_id)
            .map(|session| session.events.clone())
            .ok_or_else(|| anyhow::anyhow!("PTY session {session_id} not found"))?
    };

    let mut drained = Vec::new();
    let receiver = events
        .lock()
        .map_err(|e| anyhow::anyhow!("PTY event receiver lock poisoned: {}", e))?;
    loop {
        match receiver.try_recv() {
            Ok(event) => drained.push(event),
            Err(TryRecvError::Empty) => break,
            Err(TryRecvError::Disconnected) => break,
        }
    }
    Ok(drained)
}

fn pty_sessions() -> &'static Mutex<std::collections::HashMap<u64, PtySession>> {
    PTY_SESSIONS.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn send_pty_command(session_id: u64, command: PtyCommand) -> anyhow::Result<()> {
    let tx = {
        let sessions = pty_sessions()
            .lock()
            .map_err(|e| anyhow::anyhow!("PTY session registry lock poisoned: {}", e))?;
        sessions
            .get(&session_id)
            .map(|session| session.tx.clone())
            .ok_or_else(|| anyhow::anyhow!("PTY session {session_id} not found"))?
    };
    tx.send(command)
        .map_err(|_| anyhow::anyhow!("PTY session {session_id} is closed"))
}

fn run_pty_session(
    session_id: u64,
    paths: LinuxEnvPaths,
    workdir: String,
    tail_args: Vec<String>,
    cols: u16,
    rows: u16,
    command_rx: Receiver<PtyCommand>,
    event_tx: Sender<PtyEvent>,
) -> anyhow::Result<()> {
    #[cfg(not(unix))]
    {
        let _ = (paths, workdir, tail_args, cols, rows, command_rx);
        anyhow::bail!("PTY sessions require a Unix host");
    }

    #[cfg(unix)]
    {
        let (master_fd, slave_fd) = open_host_pty(cols, rows)?;
        let master_for_read = dup_fd(master_fd)?;
        let master_for_write = dup_fd(master_fd)?;

        let mut command = build_proot_command(
            &paths,
            &workdir,
            &tail_args.iter().map(String::as_str).collect::<Vec<_>>(),
        );
        let slave_stdin = dup_fd(slave_fd)?;
        let slave_stdout = dup_fd(slave_fd)?;
        let slave_ctty = dup_fd(slave_fd)?;
        command.stdin(unsafe { Stdio::from_raw_fd(slave_stdin) });
        command.stdout(unsafe { Stdio::from_raw_fd(slave_stdout) });
        command.stderr(unsafe { Stdio::from_raw_fd(slave_fd) });
        configure_pty_child_process(&mut command, slave_ctty);

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                close_fd(master_fd);
                close_fd(master_for_read);
                close_fd(master_for_write);
                close_fd(slave_ctty);
                return Err(error.into());
            }
        };
        close_fd(master_fd);
        close_fd(slave_ctty);

        let reader = spawn_pty_reader(session_id, master_for_read, event_tx.clone());
        let mut writer = unsafe { File::from_raw_fd(master_for_write) };
        let mut close_requested = false;

        loop {
            match command_rx.recv_timeout(PTY_EVENT_FLUSH) {
                Ok(PtyCommand::Write(data)) => {
                    if let Err(error) = writer.write_all(data.as_bytes()) {
                        let _ = event_tx.send(PtyEvent {
                            session_id,
                            kind: PtyEventKind::Log,
                            data: error.to_string(),
                            exit_code: None,
                        });
                    }
                }
                Ok(PtyCommand::Resize { cols, rows }) => {
                    set_pty_size(writer_fd(&writer), cols, rows);
                }
                Ok(PtyCommand::Close) => {
                    close_requested = true;
                    terminate_process_group(&child, SIGTERM);
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    close_requested = true;
                    terminate_process_group(&child, SIGTERM);
                }
            }

            if let Some(status) = child.try_wait()? {
                let code = status
                    .code()
                    .unwrap_or(if close_requested { -1 } else { 0 });
                let _ = event_tx.send(PtyEvent {
                    session_id,
                    kind: PtyEventKind::Exit,
                    data: String::new(),
                    exit_code: Some(code),
                });
                break;
            }

            if close_requested && wait_for_child_exit(&mut child, PROCESS_EXIT_GRACE).is_none() {
                terminate_process_group(&child, SIGKILL);
                let _ = child.kill();
            }
        }

        drop(writer);
        let _ = reader.join();
        let _ = event_tx.send(PtyEvent {
            session_id,
            kind: PtyEventKind::Closed,
            data: String::new(),
            exit_code: None,
        });
        Ok(())
    }
}

#[cfg(unix)]
fn configure_pty_child_process(command: &mut std::process::Command, slave_ctty: i32) {
    unsafe {
        command.pre_exec(move || {
            if setsid() < 0 {
                return Err(std::io::Error::last_os_error());
            }
            if ioctl(slave_ctty, TIOCSCTTY, 0) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
}

#[cfg(unix)]
fn open_host_pty(cols: u16, rows: u16) -> anyhow::Result<(i32, i32)> {
    let winsize = Winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let mut master = -1;
    let mut slave = -1;
    let result = unsafe {
        openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),
            std::ptr::null(),
            &winsize,
        )
    };
    if result != 0 || master < 0 || slave < 0 {
        anyhow::bail!("openpty failed");
    }
    Ok((master, slave))
}

#[cfg(unix)]
fn dup_fd(fd: i32) -> anyhow::Result<i32> {
    let duplicated = unsafe { dup(fd) };
    if duplicated < 0 {
        anyhow::bail!("dup({fd}) failed");
    }
    Ok(duplicated)
}

#[cfg(unix)]
fn close_fd(fd: i32) {
    if fd >= 0 {
        unsafe {
            let _ = close(fd);
        }
    }
}

#[cfg(unix)]
fn set_pty_size(fd: i32, cols: u16, rows: u16) {
    let winsize = Winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    unsafe {
        let _ = ioctl(fd, TIOCSWINSZ, &winsize);
    }
}

#[cfg(unix)]
fn writer_fd(file: &File) -> i32 {
    use std::os::fd::AsRawFd;
    file.as_raw_fd()
}

#[cfg(unix)]
fn spawn_pty_reader(session_id: u64, master_fd: i32, event_tx: Sender<PtyEvent>) -> JoinHandle<()> {
    thread::spawn(move || {
        let mut file = unsafe { File::from_raw_fd(master_fd) };
        let mut buffer = [0u8; 4096];
        loop {
            match file.read(&mut buffer) {
                Ok(0) => break,
                Ok(read) => {
                    let data = String::from_utf8_lossy(&buffer[..read]).to_string();
                    if event_tx
                        .send(PtyEvent {
                            session_id,
                            kind: PtyEventKind::Output,
                            data,
                            exit_code: None,
                        })
                        .is_err()
                    {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    })
}
