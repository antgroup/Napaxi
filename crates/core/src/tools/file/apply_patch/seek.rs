//! Locate a hunk pattern inside a file with progressive leniency.
//!
//! Strategy, in order:
//!   1. Exact line match.
//!   2. Ignore trailing whitespace per line.
//!   3. Ignore leading and trailing whitespace per line.
//!   4. Normalise common Unicode punctuation (typographic dashes / quotes /
//!      spaces) to ASCII, then compare trimmed.
//!
//! When `eof` is true the search starts at the natural end of file so that
//! patterns intended to align with the last lines are anchored there first,
//! falling back to `start` if not found.
//!
//! The algorithm follows the behaviour described in the OpenAI Codex
//! `apply-patch` crate (Apache-2.0). Implementation is rewritten in napaxi
//! to drop the codex executor-sandbox dependency chain.

pub(super) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    if pattern.is_empty() {
        return Some(start);
    }
    if pattern.len() > lines.len() {
        return None;
    }
    let search_start = if eof && lines.len() >= pattern.len() {
        lines.len() - pattern.len()
    } else {
        start.min(lines.len().saturating_sub(pattern.len()))
    };

    if let Some(idx) = search(lines, pattern, search_start, exact_match) {
        return Some(idx);
    }
    if let Some(idx) = search(lines, pattern, search_start, rstrip_match) {
        return Some(idx);
    }
    if let Some(idx) = search(lines, pattern, search_start, trim_match) {
        return Some(idx);
    }
    if let Some(idx) = search(lines, pattern, search_start, normalised_match) {
        return Some(idx);
    }
    None
}

fn search<F>(lines: &[String], pattern: &[String], from: usize, matcher: F) -> Option<usize>
where
    F: Fn(&str, &str) -> bool,
{
    let last = lines.len().saturating_sub(pattern.len());
    (from..=last).find(|&i| {
        pattern
            .iter()
            .enumerate()
            .all(|(p_idx, pat)| matcher(&lines[i + p_idx], pat))
    })
}

fn exact_match(line: &str, pattern: &str) -> bool {
    line == pattern
}

fn rstrip_match(line: &str, pattern: &str) -> bool {
    line.trim_end() == pattern.trim_end()
}

fn trim_match(line: &str, pattern: &str) -> bool {
    line.trim() == pattern.trim()
}

fn normalised_match(line: &str, pattern: &str) -> bool {
    normalise(line) == normalise(pattern)
}

fn normalise(input: &str) -> String {
    input
        .trim()
        .chars()
        .map(|c| match c {
            '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2015}'
            | '\u{2212}' => '-',
            '\u{2018}' | '\u{2019}' | '\u{201A}' | '\u{201B}' => '\'',
            '\u{201C}' | '\u{201D}' | '\u{201E}' | '\u{201F}' => '"',
            '\u{00A0}' | '\u{2002}' | '\u{2003}' | '\u{2004}' | '\u{2005}' | '\u{2006}'
            | '\u{2007}' | '\u{2008}' | '\u{2009}' | '\u{200A}' | '\u{202F}' | '\u{205F}'
            | '\u{3000}' => ' ',
            other => other,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::seek_sequence;

    fn v(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn exact_match_finds_sequence() {
        assert_eq!(
            seek_sequence(&v(&["foo", "bar", "baz"]), &v(&["bar", "baz"]), 0, false),
            Some(1)
        );
    }

    #[test]
    fn rstrip_match_ignores_trailing_whitespace() {
        assert_eq!(
            seek_sequence(&v(&["foo   ", "bar\t"]), &v(&["foo", "bar"]), 0, false),
            Some(0)
        );
    }

    #[test]
    fn trim_match_ignores_both_sides() {
        assert_eq!(
            seek_sequence(&v(&["  foo  ", "  bar "]), &v(&["foo", "bar"]), 0, false),
            Some(0)
        );
    }

    #[test]
    fn unicode_normalisation_handles_smart_quotes_and_dashes() {
        assert_eq!(
            seek_sequence(
                &v(&["let s = \u{201C}hello\u{201D};", "x\u{2014}y"]),
                &v(&["let s = \"hello\";", "x-y"]),
                0,
                false
            ),
            Some(0)
        );
    }

    #[test]
    fn pattern_longer_than_input_returns_none() {
        assert_eq!(
            seek_sequence(&v(&["one"]), &v(&["a", "b", "c"]), 0, false),
            None
        );
    }

    #[test]
    fn empty_pattern_returns_start() {
        assert_eq!(seek_sequence(&v(&["a", "b"]), &v(&[]), 1, false), Some(1));
    }

    #[test]
    fn eof_anchored_search_prefers_tail() {
        let lines = v(&["x", "tail", "x", "tail"]);
        let pattern = v(&["tail"]);
        assert_eq!(seek_sequence(&lines, &pattern, 0, true), Some(3));
    }

    #[test]
    fn resumes_search_from_start_offset() {
        let lines = v(&["dup", "x", "dup", "y"]);
        let pattern = v(&["dup"]);
        assert_eq!(seek_sequence(&lines, &pattern, 1, false), Some(2));
    }
}
