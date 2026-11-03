use super::{
    CONTEXT_GUARD_HARD_MIN_RATIO, CONTEXT_GUARD_HARD_MIN_TOKENS, ContextWindowInfo,
    DEFAULT_AGENT_COMPACTION_RESERVE_TOKENS_FLOOR, MidTurnPrecheckStatus, mid_turn_hard_precheck,
};

fn window(effective_tokens: usize) -> ContextWindowInfo {
    ContextWindowInfo {
        native_tokens: effective_tokens,
        native_source: "config",
        effective_tokens,
        effective_source: "config",
    }
}

// AC-2: soft precheck disabled / floor still triggers. Whatever the
// configured reserve is, the check is independent of `settings.enabled`
// and `trigger_ratio` — those are not even arguments here.
#[test]
fn fits_when_prompt_leaves_room_above_floor_reserve() {
    let w = window(10_000);
    let configured_reserve = 2_000;
    // reserve = max(floor=4096, hard_floor=max(4000, 1000)=4000, configured=2000) = 4096
    // prompt_budget = 10000 - 4096 = 5904; prompt_tokens=5000 ≤ budget → fits,
    // remaining = 5904 - 5000 = 904.
    let status = mid_turn_hard_precheck(w, 5_000, configured_reserve, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Fits {
            remaining_prompt_budget_tokens: 904
        }
    );
}

#[test]
fn overflow_when_prompt_plus_floor_reserve_exceeds_window() {
    let w = window(10_000);
    // prompt=6000, floor_reserve=4096 → prompt_budget=5904, overflow=96.
    let status = mid_turn_hard_precheck(w, 6_000, 0, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Overflow {
            overflow_tokens: 96
        }
    );
}

#[test]
fn configured_reserve_above_floor_is_respected() {
    // configured_reserve (8192) > floor (4096); we should reserve 8192.
    let w = window(10_000);
    // prompt=1000, budget = 10000 - 8192 = 1808; remaining = 808 → fits.
    let status = mid_turn_hard_precheck(w, 1_000, 8_192, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Fits {
            remaining_prompt_budget_tokens: 808
        }
    );
    // prompt=5000, budget = 1808; overflow = 5000 - 1808 = 3192.
    let status = mid_turn_hard_precheck(w, 5_000, 8_192, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Overflow {
            overflow_tokens: 3_192
        }
    );
}

#[test]
fn floor_reserve_dominates_small_configured_reserve() {
    // tiny configured reserve must not raise the floor's protection.
    let w = window(10_000);
    let status = mid_turn_hard_precheck(w, 6_000, 100, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Overflow {
            overflow_tokens: 96
        }
    );
}

#[test]
fn hard_floor_ratio_can_raise_floor_above_default() {
    // very large window: hard_floor = max(4000, 0.10 * 200_000 = 20000) = 20000
    // floor_reserve = max(4096, 20000) = 20000.
    let w = window(200_000);
    // prompt=180_000, budget = 200_000 - 20_000 = 180_000 → fits with 0.
    let status = mid_turn_hard_precheck(w, 180_000, 0, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Fits {
            remaining_prompt_budget_tokens: 0
        }
    );
    // prompt=180_001 → overflow=1.
    let status = mid_turn_hard_precheck(w, 180_001, 0, 0);
    assert_eq!(
        status,
        MidTurnPrecheckStatus::Overflow { overflow_tokens: 1 }
    );
}

#[test]
fn missing_window_is_always_overflow() {
    let w = window(0);
    assert_eq!(
        mid_turn_hard_precheck(w, 0, 0, 0),
        MidTurnPrecheckStatus::Overflow { overflow_tokens: 0 }
    );
}

#[test]
fn floor_constants_align_with_context_guard_floor() {
    // Make sure floor reserve uses the same constants the turn-start
    // context_guard uses, so the mid-turn check never tightens the bar.
    let budget = 10_000_usize;
    let hard_floor = CONTEXT_GUARD_HARD_MIN_TOKENS
        .max(((budget as f64) * CONTEXT_GUARD_HARD_MIN_RATIO).round() as usize);
    // hard_floor for 10000 = max(4000, 1000) = 4000; floor_reserve = max(4096, 4000) = 4096.
    assert_eq!(hard_floor, 4_000);
    assert!(DEFAULT_AGENT_COMPACTION_RESERVE_TOKENS_FLOOR >= hard_floor);
}
