//! Small, explicit DNS domain classification for alert noise reduction.

use rusqlite::Connection;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DomainCategory {
    Common,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DomainClassification {
    pub category: DomainCategory,
    pub family: Option<&'static str>,
}

#[derive(Debug, Clone, Copy)]
struct DomainFamilyRule {
    family: &'static str,
    suffixes: &'static [&'static str],
}

const DOMAIN_FAMILIES: &[DomainFamilyRule] = &[
    DomainFamilyRule {
        family: "Apple / iCloud",
        suffixes: &["apple.com", "icloud.com", "apple-dns.net", "mzstatic.com"],
    },
    DomainFamilyRule {
        family: "Google",
        suffixes: &[
            "google.com",
            "gstatic.com",
            "googleapis.com",
            "googlevideo.com",
            "ggpht.com",
        ],
    },
    DomainFamilyRule {
        family: "Microsoft / Office",
        suffixes: &[
            "microsoft.com",
            "microsoftonline.com",
            "office.com",
            "office.net",
            "live.com",
            "outlook.com",
            "msftconnecttest.com",
            "msftncsi.com",
        ],
    },
    DomainFamilyRule {
        family: "Netflix",
        suffixes: &["netflix.com", "nflxvideo.net", "nflximg.net", "nflxso.net"],
    },
];

/// Short UI / API explanation string (deterministic, no ML).
pub fn explain_domain(domain: &str) -> String {
    let c = classify_domain(domain);
    match c.category {
        DomainCategory::Common => c
            .family
            .map(|f| format!("Known service bucket: {f}"))
            .unwrap_or_else(|| "Known service pattern".to_string()),
        DomainCategory::Unknown => "Unknown (no bundled family match)".to_string(),
    }
}

/// Applies local `domain_feedback` overrides when `conn` is provided.
pub fn classify_domain_with_feedback(
    conn: Option<&Connection>,
    domain: &str,
) -> DomainClassification {
    if let Some(c) = conn {
        if let Some(v) = crate::storage::feedback::get_verdict(c, domain) {
            match v.as_str() {
                "safe" => {
                    return DomainClassification {
                        category: DomainCategory::Common,
                        family: None,
                    };
                }
                "suspicious" => {
                    return DomainClassification {
                        category: DomainCategory::Unknown,
                        family: None,
                    };
                }
                _ => {}
            }
        }
    }
    classify_domain(domain)
}

pub fn classify_domain(domain: &str) -> DomainClassification {
    let normalized = normalize_domain(domain);
    for rule in DOMAIN_FAMILIES {
        if rule
            .suffixes
            .iter()
            .any(|suffix| matches_domain_suffix(&normalized, suffix))
        {
            return DomainClassification {
                category: DomainCategory::Common,
                family: Some(rule.family),
            };
        }
    }

    DomainClassification {
        category: DomainCategory::Unknown,
        family: None,
    }
}

fn normalize_domain(domain: &str) -> String {
    domain.trim().trim_end_matches('.').to_ascii_lowercase()
}

fn matches_domain_suffix(domain: &str, suffix: &str) -> bool {
    domain == suffix
        || domain
            .strip_suffix(suffix)
            .is_some_and(|prefix| prefix.ends_with('.'))
}

#[cfg(test)]
mod tests {
    use super::{classify_domain, DomainCategory};

    #[test]
    fn matches_known_family_suffix() {
        let hit = classify_domain("api.apple.com");
        assert_eq!(hit.category, DomainCategory::Common);
        assert_eq!(hit.family, Some("Apple / iCloud"));
    }

    #[test]
    fn ignores_partial_suffix_matches() {
        let miss = classify_domain("notgoogleapis.com.example.org");
        assert_eq!(miss.category, DomainCategory::Unknown);
        assert_eq!(miss.family, None);
    }

    #[test]
    fn normalizes_case_and_trailing_dot() {
        let hit = classify_domain("WWW.GOOGLE.COM.");
        assert_eq!(hit.category, DomainCategory::Common);
        assert_eq!(hit.family, Some("Google"));
    }
}
