//! Rule-based alert prioritization and future correlation (Phase 7+).
//!
//! Keep logic **inspectable** — no opaque ML.

/// Maps stored `severity` strings to UI tiers.
pub fn priority_tier(severity: &str) -> &'static str {
    let s = severity.to_ascii_lowercase();
    match s.as_str() {
        "critical" | "high" | "error" => "high",
        "medium" | "warn" | "warning" => "medium",
        _ => "low",
    }
}
