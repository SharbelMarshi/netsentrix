//! Small shared helpers.

#[allow(dead_code)]
pub fn trim_ascii_ws(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_ascii_whitespace())
}
