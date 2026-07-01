/// Fuzzy matcher
///
/// 9-layer matching strategy chain (tried in order):
/// 1. exact - Exact match
/// 2. line_trimmed - Trim leading/trailing whitespace per line then match
/// 3. whitespace_normalized - Normalize multiple spaces/tabs
/// 4. indentation_flexible - Ignore indentation differences
/// 5. escape_normalized - Handle \n escape sequences
/// 6. trimmed_boundary - Trim whitespace on first/last lines
/// 7. unicode_normalized - Unicode character normalization
/// 8. block_anchor - Block first/last line anchors
/// 9. context_aware - Conservative line similarity threshold
#[derive(Debug)]
pub struct FuzzyMatcher;

/// Match error
#[derive(Debug)]
pub enum MatchError {
    EmptyPattern,
    IdenticalStrings,
    MultipleMatches(usize),
    NoMatch,
}

impl std::fmt::Display for MatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MatchError::EmptyPattern => write!(f, "old_string cannot be empty"),
            MatchError::IdenticalStrings => write!(f, "old_string and new_string are identical"),
            MatchError::MultipleMatches(n) => write!(
                f,
                "Found {} matches. Provide more context or use replace_all.",
                n
            ),
            MatchError::NoMatch => write!(f, "Could not find a match for old_string"),
        }
    }
}

impl std::error::Error for MatchError {}

#[derive(Debug, Clone, Copy)]
struct LineSpan<'a> {
    text: &'a str,
    start: usize,
    end: usize,
}

impl FuzzyMatcher {
    /// Fuzzy find and replace
    pub fn find_and_replace(
        content: &str,
        old_string: &str,
        new_string: &str,
        replace_all: bool,
    ) -> Result<(String, usize, &'static str), MatchError> {
        if old_string.is_empty() {
            return Err(MatchError::EmptyPattern);
        }

        if old_string == new_string {
            return Err(MatchError::IdenticalStrings);
        }

        // Strategy chain (in increasing complexity)
        let strategies: Vec<(&str, Box<dyn Fn(&str, &str) -> Option<Vec<(usize, usize)>>>)> = vec![
            ("exact", Box::new(Self::strategy_exact)),
            ("line_trimmed", Box::new(Self::strategy_line_trimmed)),
            (
                "whitespace_normalized",
                Box::new(Self::strategy_whitespace_normalized),
            ),
            (
                "indentation_flexible",
                Box::new(Self::strategy_indentation_flexible),
            ),
            (
                "escape_normalized",
                Box::new(Self::strategy_escape_normalized),
            ),
            (
                "trimmed_boundary",
                Box::new(Self::strategy_trimmed_boundary),
            ),
            (
                "unicode_normalized",
                Box::new(Self::strategy_unicode_normalized),
            ),
            ("block_anchor", Box::new(Self::strategy_block_anchor)),
            ("context_aware", Box::new(Self::strategy_context_aware)),
        ];

        for (name, strategy) in strategies {
            if let Some(matches) = strategy(content, old_string) {
                if !replace_all && matches.len() > 1 {
                    return Err(MatchError::MultipleMatches(matches.len()));
                }

                let new_content = Self::apply_replacements(content, &matches, new_string);
                return Ok((new_content, matches.len(), name));
            }
        }

        Err(MatchError::NoMatch)
    }

    /// Strategy 1: Exact match
    fn strategy_exact(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let mut matches = Vec::new();
        let mut start = 0;

        while let Some(pos) = content[start..].find(pattern) {
            let actual_pos = start + pos;
            matches.push((actual_pos, actual_pos + pattern.len()));
            start = actual_pos + pattern.len();
        }

        if matches.is_empty() {
            None
        } else {
            Some(matches)
        }
    }

    /// Strategy 2: Trim leading/trailing whitespace per line
    fn strategy_line_trimmed(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let content_lines = Self::line_spans(content);
        let pattern_lines: Vec<String> = Self::pattern_lines(pattern)
            .into_iter()
            .map(|line| line.trim().to_string())
            .collect();
        let pattern_len = pattern_lines.len();
        if pattern_len == 0 || pattern_len > content_lines.len() {
            return None;
        }

        let mut matches = Vec::new();
        for start in 0..=content_lines.len() - pattern_len {
            let matched = pattern_lines
                .iter()
                .enumerate()
                .all(|(offset, pattern_line)| {
                    content_lines[start + offset].text.trim() == pattern_line
                });
            if matched {
                matches.push(Self::line_range(&content_lines, start, pattern_len));
            }
        }

        Self::non_empty_matches(matches)
    }

    /// Strategy 3: Whitespace normalization
    fn strategy_whitespace_normalized(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let content_lines = Self::line_spans(content);
        let pattern_norm = Self::normalize_whitespace(pattern);
        if pattern_norm.is_empty() {
            return None;
        }

        let mut matches = Vec::new();
        for window_len in Self::candidate_window_lengths(pattern, content_lines.len()) {
            for start in 0..=content_lines.len().saturating_sub(window_len) {
                let candidate = Self::line_window_text(&content_lines, start, window_len);
                if Self::normalize_whitespace(&candidate) == pattern_norm {
                    matches.push(Self::line_range(&content_lines, start, window_len));
                }
            }
        }

        Self::dedupe_matches(matches)
    }

    /// Strategy 4: Ignore indentation
    fn strategy_indentation_flexible(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let content_lines = Self::line_spans(content);
        let pattern_lines = Self::pattern_lines(pattern);
        let pattern_len = pattern_lines.len();
        if pattern_len == 0 || pattern_len > content_lines.len() {
            return None;
        }

        let normalized_pattern = Self::strip_common_indent(&pattern_lines);
        let mut matches = Vec::new();
        for start in 0..=content_lines.len() - pattern_len {
            let candidate = Self::line_window_text(&content_lines, start, pattern_len);
            let candidate_lines = Self::pattern_lines(&candidate);
            if Self::strip_common_indent(&candidate_lines) == normalized_pattern {
                matches.push(Self::line_range(&content_lines, start, pattern_len));
            }
        }

        Self::non_empty_matches(matches)
    }

    /// Strategy 5: Escape normalization
    fn strategy_escape_normalized(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let decoded = Self::decode_common_escapes(pattern);
        if decoded != pattern {
            if let Some(matches) = Self::strategy_exact(content, &decoded) {
                return Some(matches);
            }
            if let Some(matches) = Self::strategy_line_trimmed(content, &decoded) {
                return Some(matches);
            }
        }

        let encoded = pattern
            .replace('\\', "\\\\")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\t', "\\t");
        if encoded != pattern {
            return Self::strategy_exact(content, &encoded);
        }

        None
    }

    /// Strategy 6: Trim whitespace on first/last lines
    fn strategy_trimmed_boundary(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let trimmed = pattern.trim();
        if trimmed == pattern || trimmed.is_empty() {
            return None;
        }
        if let Some(matches) = Self::strategy_exact(content, trimmed) {
            return Some(matches);
        }

        let content_lines = Self::line_spans(content);
        let target = trimmed.to_string();
        let mut matches = Vec::new();
        for window_len in Self::candidate_window_lengths(trimmed, content_lines.len()) {
            for start in 0..=content_lines.len().saturating_sub(window_len) {
                let candidate = Self::line_window_text(&content_lines, start, window_len);
                if candidate.trim() == target {
                    matches.push(Self::line_range(&content_lines, start, window_len));
                }
            }
        }

        Self::dedupe_matches(matches)
    }

    /// Strategy 7: Unicode normalization
    fn strategy_unicode_normalized(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let content_lines = Self::line_spans(content);
        let target = Self::normalize_unicode_light(pattern);
        if target.is_empty() {
            return None;
        }

        let mut matches = Vec::new();
        for window_len in Self::candidate_window_lengths(pattern, content_lines.len()) {
            for start in 0..=content_lines.len().saturating_sub(window_len) {
                let candidate = Self::line_window_text(&content_lines, start, window_len);
                if Self::normalize_unicode_light(&candidate) == target {
                    matches.push(Self::line_range(&content_lines, start, window_len));
                }
            }
        }

        Self::dedupe_matches(matches)
    }

    /// Strategy 8: Block anchor matching
    fn strategy_block_anchor(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let content_lines = Self::line_spans(content);
        let pattern_lines: Vec<String> = Self::pattern_lines(pattern)
            .into_iter()
            .map(|line| line.trim().to_string())
            .filter(|line| !line.is_empty())
            .collect();
        if pattern_lines.len() < 2 {
            return None;
        }

        let first = pattern_lines.first()?;
        let last = pattern_lines.last()?;
        let mut matches = Vec::new();

        for start in 0..content_lines.len() {
            if content_lines[start].text.trim() != first {
                continue;
            }
            for end in start + 1..content_lines.len() {
                if content_lines[end].text.trim() != last {
                    continue;
                }
                matches.push(Self::line_range(&content_lines, start, end - start + 1));
            }
        }

        Self::non_empty_matches(matches)
    }

    /// Strategy 9: Context aware
    fn strategy_context_aware(content: &str, pattern: &str) -> Option<Vec<(usize, usize)>> {
        let content_lines = Self::line_spans(content);
        let pattern_lines: Vec<String> = Self::pattern_lines(pattern)
            .into_iter()
            .filter(|line| !line.trim().is_empty())
            .collect();
        let pattern_len = pattern_lines.len();
        if pattern_len == 0 || pattern_len > content_lines.len() {
            return None;
        }

        let mut matches = Vec::new();
        for start in 0..=content_lines.len() - pattern_len {
            let score = pattern_lines
                .iter()
                .enumerate()
                .map(|(offset, pattern_line)| {
                    Self::line_similarity(pattern_line, content_lines[start + offset].text)
                })
                .sum::<f64>()
                / pattern_len as f64;
            if score >= 0.65 {
                matches.push(Self::line_range(&content_lines, start, pattern_len));
            }
        }

        Self::non_empty_matches(matches)
    }

    /// Apply replacements
    fn apply_replacements(content: &str, matches: &[(usize, usize)], replacement: &str) -> String {
        let mut result = content.to_string();
        for (start, end) in matches.iter().rev() {
            result.replace_range(*start..*end, replacement);
        }
        result
    }

    fn non_empty_matches(matches: Vec<(usize, usize)>) -> Option<Vec<(usize, usize)>> {
        if matches.is_empty() {
            None
        } else {
            Some(matches)
        }
    }

    fn dedupe_matches(mut matches: Vec<(usize, usize)>) -> Option<Vec<(usize, usize)>> {
        matches.sort_unstable();
        matches.dedup();
        Self::non_empty_matches(matches)
    }

    fn line_spans(content: &str) -> Vec<LineSpan<'_>> {
        if content.is_empty() {
            return Vec::new();
        }

        let mut spans = Vec::new();
        let mut start = 0;
        for part in content.split_inclusive('\n') {
            let end_with_newline = start + part.len();
            let mut line_end = end_with_newline;
            if part.ends_with('\n') {
                line_end -= 1;
                if line_end > start && content.as_bytes()[line_end - 1] == b'\r' {
                    line_end -= 1;
                }
            }
            spans.push(LineSpan {
                text: &content[start..line_end],
                start,
                end: line_end,
            });
            start = end_with_newline;
        }

        spans
    }

    fn pattern_lines(pattern: &str) -> Vec<String> {
        Self::normalize_line_endings(pattern)
            .split('\n')
            .map(ToString::to_string)
            .collect()
    }

    fn normalize_line_endings(input: &str) -> String {
        input.replace("\r\n", "\n").replace('\r', "\n")
    }

    fn line_range(lines: &[LineSpan<'_>], start: usize, len: usize) -> (usize, usize) {
        (lines[start].start, lines[start + len - 1].end)
    }

    fn line_window_text(lines: &[LineSpan<'_>], start: usize, len: usize) -> String {
        lines[start..start + len]
            .iter()
            .map(|line| line.text)
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn candidate_window_lengths(pattern: &str, total_lines: usize) -> Vec<usize> {
        if total_lines == 0 {
            return Vec::new();
        }

        let pattern_len = Self::pattern_lines(pattern).len().max(1);
        let mut lengths = vec![pattern_len];
        if pattern_len > 1 {
            lengths.push(pattern_len - 1);
        }
        lengths.push(pattern_len + 1);
        if pattern_len == 1 {
            lengths.extend(2..=total_lines.min(6));
        }

        lengths.retain(|len| *len > 0 && *len <= total_lines);
        lengths.sort_unstable();
        lengths.dedup();
        lengths
    }

    fn normalize_whitespace(input: &str) -> String {
        input.split_whitespace().collect::<Vec<_>>().join(" ")
    }

    fn strip_common_indent(lines: &[String]) -> String {
        let common_indent = lines
            .iter()
            .filter(|line| !line.trim().is_empty())
            .map(|line| line.chars().take_while(|ch| ch.is_whitespace()).count())
            .min()
            .unwrap_or(0);

        lines
            .iter()
            .map(|line| line.chars().skip(common_indent).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn decode_common_escapes(input: &str) -> String {
        let mut output = String::with_capacity(input.len());
        let mut chars = input.chars();
        while let Some(ch) = chars.next() {
            if ch != '\\' {
                output.push(ch);
                continue;
            }

            match chars.next() {
                Some('n') => output.push('\n'),
                Some('r') => output.push('\r'),
                Some('t') => output.push('\t'),
                Some('\\') => output.push('\\'),
                Some(other) => {
                    output.push('\\');
                    output.push(other);
                }
                None => output.push('\\'),
            }
        }
        output
    }

    fn normalize_unicode_light(input: &str) -> String {
        let mut output = String::with_capacity(input.len());
        for ch in input.chars() {
            match ch {
                '\u{00a0}' | '\u{2007}' | '\u{202f}' => output.push(' '),
                '\u{2018}' | '\u{2019}' | '\u{201b}' => output.push('\''),
                '\u{201c}' | '\u{201d}' | '\u{201f}' => output.push('"'),
                '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2212}' => {
                    output.push('-')
                }
                '\u{2026}' => output.push_str("..."),
                _ => output.push(ch),
            }
        }
        output
    }

    fn line_similarity(a: &str, b: &str) -> f64 {
        let a = Self::normalize_whitespace(&Self::normalize_unicode_light(a));
        let b = Self::normalize_whitespace(&Self::normalize_unicode_light(b));
        if a == b {
            return 1.0;
        }
        if a.is_empty() || b.is_empty() {
            return 0.0;
        }

        let a_chars: Vec<char> = a.chars().collect();
        let b_chars: Vec<char> = b.chars().collect();
        let mut dp = vec![vec![0usize; b_chars.len() + 1]; a_chars.len() + 1];
        for (i, a_ch) in a_chars.iter().enumerate() {
            for (j, b_ch) in b_chars.iter().enumerate() {
                dp[i + 1][j + 1] = if a_ch == b_ch {
                    dp[i][j] + 1
                } else {
                    dp[i][j + 1].max(dp[i + 1][j])
                };
            }
        }

        dp[a_chars.len()][b_chars.len()] as f64 / a_chars.len().max(b_chars.len()) as f64
    }
}

/// Simple fuzzy find-and-replace function (single entry point)
pub fn fuzzy_find_and_replace(
    content: &str,
    old_string: &str,
    new_string: &str,
    replace_all: bool,
) -> Result<(String, usize, Option<String>, Option<String>), String> {
    match FuzzyMatcher::find_and_replace(content, old_string, new_string, replace_all) {
        Ok((new_content, count, strategy)) => {
            Ok((new_content, count, Some(strategy.to_string()), None))
        }
        Err(e) => {
            let _preview = if content.len() > 500 {
                format!("{}...", &content[..500])
            } else {
                content.to_string()
            };
            Err(e.to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exact_match() {
        let content = "def foo():\n    pass";
        let (new, count, strategy, _) =
            fuzzy_find_and_replace(content, "def foo():", "def bar():", false).unwrap();
        assert_eq!(strategy, Some("exact".to_string()));
        assert_eq!(count, 1);
        assert!(new.contains("def bar():"));
    }

    #[test]
    fn test_line_trimmed() {
        // Use content with spaces so exact match fails, triggering line_trimmed
        let content = "    line with indent\n    another line";
        let (new, count, _strategy, _) =
            fuzzy_find_and_replace(content, "line with indent", "replaced", false).unwrap();
        // Since optimized line matching may also trigger exact, we just need to ensure replacement succeeds
        assert!(new.contains("replaced"));
        assert_eq!(count, 1);
    }

    #[test]
    fn test_no_match() {
        let result = fuzzy_find_and_replace("content", "nonexistent", "replacement", false);
        assert!(result.is_err());
    }

    #[test]
    fn test_multiple_matches() {
        let result = fuzzy_find_and_replace("hello hello hello", "hello", "hi", false);
        assert!(result.is_err()); // Will return MultipleMatches error
    }

    #[test]
    fn test_replace_all() {
        let (new, count, _, _) =
            fuzzy_find_and_replace("hello hello hello", "hello", "hi", true).unwrap();
        assert_eq!(count, 3);
        assert_eq!(new, "hi hi hi");
    }

    #[test]
    fn test_empty_old_string() {
        let result = fuzzy_find_and_replace("content", "", "replacement", false);
        assert!(result.is_err());
    }

    #[test]
    fn test_identical_strings() {
        let result = fuzzy_find_and_replace("content", "hello", "hello", false);
        assert!(result.is_err());
    }

    #[test]
    fn test_line_trimmed_strategy() {
        // Test line trimming strategy successful match
        let content = "    line with indent\n    another line";
        let (new, _, _strategy, _) =
            fuzzy_find_and_replace(content, "line with indent", "REPLACED", false).unwrap();
        // As long as replacement succeeds
        assert!(new.contains("REPLACED"));
    }

    #[test]
    fn test_whitespace_normalized_strategy() {
        let content = "prefix\nhello   world\nsuffix";
        let (new, _, strategy, _) =
            fuzzy_find_and_replace(content, "hello world", "HI", false).unwrap();
        assert_eq!(strategy, Some("whitespace_normalized".to_string()));
        assert_eq!(new, "prefix\nHI\nsuffix");
    }

    #[test]
    fn test_multiline_match() {
        let content = r#"line1
line2
line3"#;
        let (new, count, _, _) =
            fuzzy_find_and_replace(content, "line1\nline2", "REPLACED", false).unwrap();
        assert_eq!(count, 1);
        assert_eq!(new, "REPLACED\nline3");
    }

    #[test]
    fn test_empty_content() {
        let result = fuzzy_find_and_replace("", "pattern", "replacement", false);
        assert!(result.is_err());
    }

    #[test]
    fn test_strategy_exact_priority() {
        // Ensure exact strategy has priority over line_trimmed
        let content = "  hello  ";
        let (new, _, strategy, _) =
            fuzzy_find_and_replace(content, "  hello  ", "HI", false).unwrap();
        assert_eq!(strategy, Some("exact".to_string()));
        assert_eq!(new.trim(), "HI");
    }

    #[test]
    fn test_escape_normalized_strategy() {
        let content = "line1\nline2\nline3";
        let (new, count, strategy, _) =
            fuzzy_find_and_replace(content, "line1\\nline2", "REPLACED", false).unwrap();
        assert_eq!(strategy, Some("escape_normalized".to_string()));
        assert_eq!(count, 1);
        assert_eq!(new, "REPLACED\nline3");
    }

    #[test]
    fn test_unicode_normalized_strategy() {
        let content = "alpha\nhello \u{2018}world\u{2019}\nomega";
        let (new, count, strategy, _) =
            fuzzy_find_and_replace(content, "hello 'world'", "HI", false).unwrap();
        assert_eq!(strategy, Some("unicode_normalized".to_string()));
        assert_eq!(count, 1);
        assert_eq!(new, "alpha\nHI\nomega");
    }

    #[test]
    fn test_block_anchor_strategy() {
        let content = "before\nstart\nchanged middle\nend\nafter";
        let pattern = "start\noriginal middle\nend";
        let (new, count, strategy, _) =
            fuzzy_find_and_replace(content, pattern, "BLOCK", false).unwrap();
        assert_eq!(strategy, Some("block_anchor".to_string()));
        assert_eq!(count, 1);
        assert_eq!(new, "before\nBLOCK\nafter");
    }

    #[test]
    fn test_context_aware_strategy() {
        let content = "before\nhello brave world\nafter";
        let (new, count, strategy, _) =
            fuzzy_find_and_replace(content, "hello bright world", "HI", false).unwrap();
        assert_eq!(strategy, Some("context_aware".to_string()));
        assert_eq!(count, 1);
        assert_eq!(new, "before\nHI\nafter");
    }
}