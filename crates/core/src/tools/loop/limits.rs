pub const DEFAULT_TOOL_TURN_LIMIT: usize = 50;
pub const UNBOUNDED_TOOL_TURN_LIMIT: usize = 1_000_000;

pub fn tool_turn_limit(max_iterations: i32) -> usize {
    match max_iterations.cmp(&0) {
        std::cmp::Ordering::Less => UNBOUNDED_TOOL_TURN_LIMIT,
        std::cmp::Ordering::Equal => DEFAULT_TOOL_TURN_LIMIT,
        std::cmp::Ordering::Greater => (max_iterations as usize).max(2),
    }
}

pub fn resolved_tool_turn_limit(turn_max_iterations: i32, config_max_iterations: i32) -> usize {
    if turn_max_iterations == 0 {
        tool_turn_limit(config_max_iterations)
    } else {
        tool_turn_limit(turn_max_iterations)
    }
}
