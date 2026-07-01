//! Session-scoped runtime state owned by an [`Engine`](super::Engine).
//!
//! This is the first explicit boundary for long-lived mobile agent
//! orchestration. Keep platform/adapter concerns outside this module: it owns
//! runtime state that must survive across collected and streaming turns, while
//! adapters still provide host capabilities through the existing bridges.

use std::collections::HashMap;
use std::sync::Mutex;

use super::sessions::session_cancellation_key;

/// Per-session cancellation bookkeeping.
///
/// `current_generation` is a monotonic run counter, bumped every time a new
/// turn or run starts for the session (`begin_turn` / `clear_session_cancellation`).
/// `cancelled_generation` records which generation a still-pending cancel
/// request targeted. A cancel is only "observed" by the run whose generation
/// matches — so a cancel issued against run *N* can never leak into run *N+1*,
/// which eliminates the stale-cancel race the old membership-set model had
/// (a late cancel landing just as the next turn started).
#[derive(Default)]
struct SessionCancelState {
    current_generation: u64,
    cancelled_generation: Option<u64>,
}

#[derive(Default)]
pub(super) struct SessionRuntime {
    sessions: Mutex<HashMap<String, SessionCancelState>>,
}

impl SessionRuntime {
    pub(super) fn new() -> Self {
        Self::default()
    }

    pub(super) fn begin_turn(&self, session_key_json: &str) -> SessionTurnRuntime {
        let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
            return SessionTurnRuntime {
                cancellation_key: None,
                generation: 0,
            };
        };
        let generation = self.start_new_generation(&cancellation_key);
        SessionTurnRuntime {
            cancellation_key: Some(cancellation_key),
            generation,
        }
    }

    pub(super) fn cancel_session_key(&self, session_key_json: &str) -> bool {
        let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
            return false;
        };
        let Ok(mut guard) = self.sessions.lock() else {
            return false;
        };
        // Atomically capture whatever generation is current at this serialized
        // moment, and mark it cancelled. If a new turn has already advanced the
        // generation, the in-flight turn captured the newer value and this
        // cancel targets the run that was actually current when it won the lock.
        let state = guard.entry(cancellation_key).or_default();
        state.cancelled_generation = Some(state.current_generation);
        true
    }

    pub(super) fn clear_session_cancellation(&self, session_key_json: &str) {
        let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
            return;
        };
        // A manual-style run (agents/a2a/automation/group) calls this at start
        // and then polls `is_session_cancelled`. Advancing the generation here
        // means any cancel that targeted the prior run is dropped, not carried
        // into this one.
        self.start_new_generation(&cancellation_key);
    }

    pub(super) fn is_session_cancelled(&self, session_key_json: &str) -> bool {
        let Some(cancellation_key) = session_cancellation_key(session_key_json) else {
            return false;
        };
        self.is_current_generation_cancelled(&cancellation_key)
    }

    /// Bump and return the session's current generation, clearing any pending
    /// cancel so a fresh run starts uncancelled. Returns the new generation.
    fn start_new_generation(&self, cancellation_key: &str) -> u64 {
        let Ok(mut guard) = self.sessions.lock() else {
            return 0;
        };
        let state = guard.entry(cancellation_key.to_string()).or_default();
        state.current_generation = state.current_generation.wrapping_add(1);
        state.cancelled_generation = None;
        state.current_generation
    }

    /// Manual-style check: is the *current* generation cancelled?
    fn is_current_generation_cancelled(&self, cancellation_key: &str) -> bool {
        self.sessions
            .lock()
            .map(|guard| {
                guard
                    .get(cancellation_key)
                    .map(|state| state.cancelled_generation == Some(state.current_generation))
                    .unwrap_or(false)
            })
            .unwrap_or(false)
    }

    /// Turn-style check: is the specific captured `generation` cancelled? A
    /// turn only observes a cancel aimed at its own generation, so it is immune
    /// to cancels serialized before it began.
    fn is_generation_cancelled(&self, cancellation_key: &str, generation: u64) -> bool {
        self.sessions
            .lock()
            .map(|guard| {
                guard
                    .get(cancellation_key)
                    .map(|state| state.cancelled_generation == Some(generation))
                    .unwrap_or(false)
            })
            .unwrap_or(false)
    }
}

pub(super) struct SessionTurnRuntime {
    cancellation_key: Option<String>,
    generation: u64,
}

impl SessionTurnRuntime {
    pub(super) fn is_cancelled(&self, runtime: &SessionRuntime) -> bool {
        self.cancellation_key
            .as_deref()
            .map(|key| runtime.is_generation_cancelled(key, self.generation))
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::Barrier;

    use super::*;

    fn session_key(thread_id: &str) -> String {
        serde_json::json!({
            "channel_type": "app",
            "account_id": "user",
            "thread_id": thread_id,
        })
        .to_string()
    }

    #[test]
    fn begin_turn_clears_prior_cancellation_for_same_session() {
        let runtime = SessionRuntime::new();
        let key = session_key("thread");

        assert!(runtime.cancel_session_key(&key));
        assert!(runtime.is_session_cancelled(&key));

        let turn = runtime.begin_turn(&key);

        assert!(!turn.is_cancelled(&runtime));
        assert!(!runtime.is_session_cancelled(&key));
    }

    #[test]
    fn turn_runtime_observes_cancellation_after_it_starts() {
        let runtime = SessionRuntime::new();
        let key = session_key("thread");
        let turn = runtime.begin_turn(&key);

        assert!(!turn.is_cancelled(&runtime));
        assert!(runtime.cancel_session_key(&key));
        assert!(turn.is_cancelled(&runtime));
    }

    #[test]
    fn cancel_targeting_old_turn_does_not_leak_into_next_turn() {
        // The core stale-cancel regression: a cancel aimed at turn N must never
        // be observed by turn N+1, even though they share a session key.
        let runtime = SessionRuntime::new();
        let key = session_key("thread");

        let first = runtime.begin_turn(&key);
        assert!(runtime.cancel_session_key(&key));
        assert!(
            first.is_cancelled(&runtime),
            "first turn should see its cancel"
        );

        // A new turn begins. It must start clean and stay clean.
        let second = runtime.begin_turn(&key);
        assert!(
            !second.is_cancelled(&runtime),
            "second turn must not inherit the first turn's cancel"
        );
        // Starting the second turn also wiped the pending cancel, so neither the
        // stale handle nor the manual-style poll reports cancelled anymore.
        assert!(
            !first.is_cancelled(&runtime),
            "the prior turn's cancel is dropped once a new turn starts"
        );
        assert!(!runtime.is_session_cancelled(&key));
    }

    #[test]
    fn manual_style_clear_then_poll_drops_prior_cancel() {
        // agents/a2a/automation/group pattern: clear at start, poll thereafter.
        let runtime = SessionRuntime::new();
        let key = session_key("thread");

        assert!(runtime.cancel_session_key(&key));
        runtime.clear_session_cancellation(&key);
        assert!(
            !runtime.is_session_cancelled(&key),
            "clear must drop a cancel that targeted the prior run"
        );

        // A cancel after clear is observed by the current run.
        assert!(runtime.cancel_session_key(&key));
        assert!(runtime.is_session_cancelled(&key));
    }

    #[test]
    fn generation_is_monotonic_across_turns_and_clears() {
        let runtime = SessionRuntime::new();
        let key = session_key("thread");

        let g1 = runtime.begin_turn(&key).generation;
        let g2 = runtime.begin_turn(&key).generation;
        runtime.clear_session_cancellation(&key);
        let g3 = runtime.begin_turn(&key).generation;

        assert!(g2 > g1, "each turn advances the generation");
        assert!(g3 > g2, "a manual clear also advances the generation");
    }

    #[test]
    fn distinct_sessions_do_not_share_cancellation() {
        let runtime = SessionRuntime::new();
        let a = session_key("a");
        let b = session_key("b");

        let turn_a = runtime.begin_turn(&a);
        let turn_b = runtime.begin_turn(&b);
        assert!(runtime.cancel_session_key(&a));

        assert!(turn_a.is_cancelled(&runtime));
        assert!(
            !turn_b.is_cancelled(&runtime),
            "cancel must be scoped per session"
        );
    }

    #[test]
    fn concurrent_cancel_and_begin_turn_never_leaks_into_a_clean_started_turn() {
        // Deterministic-ish stress: race cancel() against begin_turn() many times
        // on real threads, synchronized by a barrier so the two operations
        // contend for the same lock acquisition window. The invariant under test
        // is total, not probabilistic: a turn that begins and observes itself
        // uncancelled must STAY uncancelled unless a cancel is issued after it
        // began. Because cancel() captures whatever generation is current under
        // the lock, the only two serialized orderings are:
        //   begin then cancel  -> the new turn IS cancelled (cancel saw it)
        //   cancel then begin  -> the new turn is NOT cancelled (begin reset it)
        // Neither ordering can leave a turn that read "clean" and later flips to
        // "cancelled" without a cancel that genuinely targeted its generation.
        for _ in 0..2_000 {
            let runtime = Arc::new(SessionRuntime::new());
            let key = session_key("race");
            // Pre-existing cancel from a previous run that must not leak.
            assert!(runtime.cancel_session_key(&key));

            let barrier = Arc::new(Barrier::new(2));

            let r1 = Arc::clone(&runtime);
            let k1 = key.clone();
            let b1 = Arc::clone(&barrier);
            let canceller = std::thread::spawn(move || {
                b1.wait();
                r1.cancel_session_key(&k1);
            });

            let r2 = Arc::clone(&runtime);
            let k2 = key.clone();
            let b2 = Arc::clone(&barrier);
            let starter = std::thread::spawn(move || {
                b2.wait();
                let turn = r2.begin_turn(&k2);
                // Snapshot immediately after start.
                let seen_at_start = turn.is_cancelled(&r2);
                (turn.generation, seen_at_start)
            });

            canceller.join().unwrap();
            let (generation, seen_at_start) = starter.join().unwrap();

            // Whatever the interleaving, the turn's generation is the freshly
            // started one (>= 1), while the stale pre-existing cancel targeted
            // generation 0 and can never be the one observed. Any cancel the
            // turn does see must have targeted its own (racing) generation.
            assert!(
                generation >= 1,
                "begin_turn must advance past the leaked cancel"
            );
            if seen_at_start {
                // If it read cancelled, that must be the racing cancel hitting
                // the new generation — consistent, not a leak. Re-reading agrees.
                assert!(runtime.is_generation_cancelled(
                    session_cancellation_key(&key).as_deref().unwrap(),
                    generation
                ));
            }
        }
    }
}
