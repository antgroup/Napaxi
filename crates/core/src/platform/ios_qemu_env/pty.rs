use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};

use super::{
    ensure_setup_and_init_with_workspace_dir, normalize_workdir, qemu_env_json, qemu_session_close,
    qemu_session_open, qemu_session_read, qemu_session_resize, qemu_session_wait_output,
    qemu_session_write,
};

const PTY_READ_BUF_SIZE: usize = 16 * 1024;

static NEXT_PTY_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static PTY_SESSIONS: OnceLock<Mutex<HashMap<u64, PtySession>>> = OnceLock::new();

#[derive(Debug, Clone)]
pub enum PtyEventKind {
    Output,
    Exit,
    Closed,
    Log,
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct PtyEvent {
    pub session_id: u64,
    pub kind: PtyEventKind,
    pub data: String,
    pub exit_code: Option<i32>,
}

struct PtySession {
    events: Arc<Mutex<Receiver<PtyEvent>>>,
    join: Option<JoinHandle<()>>,
}

pub fn open_pty_session(
    files_dir: &str,
    _native_library_dir: &str,
    workspace_dir: &str,
    argv: &[String],
    workdir: Option<&str>,
    cols: u16,
    rows: u16,
) -> anyhow::Result<u64> {
    let workspace_dir = PathBuf::from(workspace_dir);
    ensure_setup_and_init_with_workspace_dir(files_dir, workspace_dir)?;
    let session_id = NEXT_PTY_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let command = session_command(argv);
    let command_c = CString::new(command.as_str())?;
    let workdir_c = CString::new(normalize_workdir(workdir))?;
    let env_json = qemu_env_json();
    let env_c = CString::new(env_json)?;
    // SAFETY: all pointers are valid NUL-terminated strings for the call;
    // the QEMU bridge copies strings before returning and owns the session.
    let rc = unsafe {
        qemu_session_open(
            command_c.as_ptr(),
            workdir_c.as_ptr(),
            env_c.as_ptr(),
            session_id,
            i32::from(cols.max(1)),
            i32::from(rows.max(1)),
        )
    };
    if rc != 0 {
        anyhow::bail!("iOS QEMU PTY session open failed with code {rc}");
    }

    let (event_tx, event_rx) = mpsc::channel();
    let join = thread::spawn(move || read_session_loop(session_id, event_tx));
    pty_sessions()
        .lock()
        .map_err(|e| anyhow::anyhow!("PTY session registry lock poisoned: {}", e))?
        .insert(
            session_id,
            PtySession {
                events: Arc::new(Mutex::new(event_rx)),
                join: Some(join),
            },
        );
    Ok(session_id)
}

pub fn write_pty_session(session_id: u64, data: &str) -> anyhow::Result<()> {
    let data_c = CString::new(data)?;
    // SAFETY: `data_c` is a valid C string for the duration of the call.
    let rc = unsafe { qemu_session_write(session_id, data_c.as_ptr()) };
    if rc != 0 {
        anyhow::bail!("iOS QEMU PTY write failed with code {rc}");
    }
    Ok(())
}

#[allow(dead_code)]
pub fn resize_pty_session(session_id: u64, cols: u16, rows: u16) -> anyhow::Result<()> {
    // SAFETY: session id belongs to the QEMU session registry; dimensions are positive.
    let rc =
        unsafe { qemu_session_resize(session_id, i32::from(cols.max(1)), i32::from(rows.max(1))) };
    if rc != 0 {
        anyhow::bail!("iOS QEMU PTY resize failed with code {rc}");
    }
    Ok(())
}

pub fn close_pty_session(session_id: u64) -> anyhow::Result<()> {
    let mut session = take_pty_session(session_id)?;
    // SAFETY: session id belongs to the QEMU session registry; closing is idempotent at the bridge boundary.
    let _ = unsafe { qemu_session_close(session_id) };
    if let Some(join) = session.join.take() {
        let _ = join.join();
    }
    Ok(())
}

pub fn close_pty_session_nonblocking(session_id: u64) -> anyhow::Result<()> {
    let _session = take_pty_session(session_id)?;
    // SAFETY: session id belongs to the QEMU session registry; reader thread will observe closure.
    let _ = unsafe { qemu_session_close(session_id) };
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
    let receiver = events
        .lock()
        .map_err(|e| anyhow::anyhow!("PTY event receiver lock poisoned: {}", e))?;
    let mut drained = Vec::new();
    loop {
        match receiver.try_recv() {
            Ok(event) => drained.push(event),
            Err(TryRecvError::Empty) => break,
            Err(TryRecvError::Disconnected) => break,
        }
    }
    Ok(drained)
}

fn take_pty_session(session_id: u64) -> anyhow::Result<PtySession> {
    pty_sessions()
        .lock()
        .map_err(|e| anyhow::anyhow!("PTY session registry lock poisoned: {}", e))?
        .remove(&session_id)
        .ok_or_else(|| anyhow::anyhow!("PTY session {session_id} not found"))
}

fn pty_sessions() -> &'static Mutex<HashMap<u64, PtySession>> {
    PTY_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn read_session_loop(session_id: u64, event_tx: mpsc::Sender<PtyEvent>) {
    let mut buffer = vec![0 as c_char; PTY_READ_BUF_SIZE];
    loop {
        // SAFETY: session id belongs to QEMU; wait only blocks until output or close.
        let ready = unsafe { qemu_session_wait_output(session_id) };
        if ready < 0 {
            let _ = event_tx.send(PtyEvent {
                session_id,
                kind: PtyEventKind::Closed,
                data: String::new(),
                exit_code: None,
            });
            return;
        }
        loop {
            buffer.fill(0);
            // SAFETY: output buffer is writable and passed with its exact length.
            let read = unsafe { qemu_session_read(session_id, buffer.as_mut_ptr(), buffer.len()) };
            if read > 0 {
                // SAFETY: the bridge NUL-terminates output_buf on successful reads.
                let data = unsafe { CStr::from_ptr(buffer.as_ptr()) }
                    .to_string_lossy()
                    .into_owned();
                if event_tx
                    .send(PtyEvent {
                        session_id,
                        kind: PtyEventKind::Output,
                        data,
                        exit_code: None,
                    })
                    .is_err()
                {
                    return;
                }
                continue;
            }
            if read == -4 {
                let _ = event_tx.send(PtyEvent {
                    session_id,
                    kind: PtyEventKind::Exit,
                    data: String::new(),
                    exit_code: None,
                });
                let _ = event_tx.send(PtyEvent {
                    session_id,
                    kind: PtyEventKind::Closed,
                    data: String::new(),
                    exit_code: None,
                });
                return;
            }
            if read < 0 {
                let _ = event_tx.send(PtyEvent {
                    session_id,
                    kind: PtyEventKind::Log,
                    data: format!("iOS QEMU PTY read failed with code {read}"),
                    exit_code: None,
                });
                return;
            }
            break;
        }
    }
}

fn session_command(argv: &[String]) -> String {
    if argv.len() >= 3 && argv[0].ends_with("/bin/sh") && argv[1] == "-lc" {
        return argv[2].clone();
    }
    if argv.len() >= 2 && argv[0].ends_with("/bin/sh") && argv[1] == "-il" {
        return "/bin/sh -il".to_string();
    }
    shell_quote_command(argv)
}

fn shell_quote_command(argv: &[String]) -> String {
    if argv.is_empty() {
        return "/bin/sh -il".to_string();
    }
    argv.iter()
        .map(|arg| format!("'{}'", arg.replace('\'', "'\\''")))
        .collect::<Vec<_>>()
        .join(" ")
}
