//! Turn execution entrypoints and the collected/streaming drivers behind them.
//!
//! The two execution modes live in submodules — [`collected`] returns the full
//! event list, [`streaming`] emits events incrementally — and share the
//! checkpoint policy defined here. `turn::mod` re-exports through this module,
//! so the `orchestration::*` paths stay stable for callers and tests.

use super::{TurnDiagnosticsRecorder, TurnInput};
use crate::types::ChatEvent;

mod collected;
mod streaming;

#[cfg(test)]
pub(crate) use collected::run_turn_with_hooks;
#[cfg(not(test))]
use collected::run_turn_with_hooks;
pub(crate) use streaming::stream_turn_with_hooks;

pub async fn run_turn<C>(input: TurnInput, mut is_cancelled: C) -> Vec<ChatEvent>
where
    C: FnMut() -> bool,
{
    let files_dir = input.files_dir.clone();
    let mut hooks = TurnDiagnosticsRecorder::new(&files_dir);
    let events = run_turn_with_hooks(input, &mut hooks, &mut is_cancelled).await;
    hooks.persist();
    events
}

pub async fn stream_turn<E, C>(input: TurnInput, mut emit: E, is_cancelled: C)
where
    E: FnMut(ChatEvent),
    C: Fn() -> bool,
{
    let files_dir = input.files_dir.clone();
    let mut hooks = TurnDiagnosticsRecorder::new(&files_dir);
    stream_turn_with_hooks(input, &mut hooks, &mut emit, is_cancelled).await;
    hooks.persist();
}

fn checkpoint_after_event(event: &ChatEvent) -> bool {
    matches!(
        event,
        ChatEvent::ToolCall { .. }
            | ChatEvent::AgentToolCall { .. }
            | ChatEvent::ToolResult { .. }
            | ChatEvent::AgentToolResult { .. }
            | ChatEvent::AgentDelegation { .. }
            | ChatEvent::AgentDelegationResult { .. }
            | ChatEvent::AskingHuman { .. }
            | ChatEvent::HumanResponse { .. }
    )
}
