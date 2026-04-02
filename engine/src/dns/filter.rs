//! Block/allow lists: one domain per line, `#` comments, lowercase normalization.

use std::collections::HashSet;
use std::path::PathBuf;

use rusqlite::Connection;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterDecision {
    Allow,
    Block,
}

#[derive(Debug, Default)]
pub struct DnsFilter {
    allow: HashSet<String>,
    block: HashSet<String>,
}

impl DnsFilter {
    pub fn load_from_paths(
        allow_paths: &[PathBuf],
        block_paths: &[PathBuf],
    ) -> anyhow::Result<Self> {
        let mut f = DnsFilter::default();
        for p in allow_paths {
            merge_file_into(&mut f.allow, p)?;
        }
        for p in block_paths {
            merge_file_into(&mut f.block, p)?;
        }
        Ok(f)
    }

    /// Append enabled block rules from SQLite (`type = dns_block`, `pattern` = domain or `*.suffix`).
    pub fn merge_db_rules(conn: &Connection) -> rusqlite::Result<HashSet<String>> {
        let mut set = HashSet::new();
        let mut stmt = conn.prepare(
            "SELECT pattern FROM rules WHERE type = 'dns_block' AND enabled = 1",
        )?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        for p in rows {
            set.insert(normalize_domain(&p?));
        }
        Ok(set)
    }

    pub fn merge_db_allow_rules(conn: &Connection) -> rusqlite::Result<HashSet<String>> {
        let mut set = HashSet::new();
        let mut stmt = conn.prepare(
            "SELECT pattern FROM rules WHERE type = 'dns_allow' AND enabled = 1",
        )?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        for p in rows {
            set.insert(normalize_domain(&p?));
        }
        Ok(set)
    }

    pub fn reload_from_paths(
        &mut self,
        allow_paths: &[PathBuf],
        block_paths: &[PathBuf],
    ) -> anyhow::Result<()> {
        let fresh = Self::load_from_paths(allow_paths, block_paths)?;
        self.allow = fresh.allow;
        self.block = fresh.block;
        Ok(())
    }

    pub fn reload_all(
        &mut self,
        allow_paths: &[PathBuf],
        block_paths: &[PathBuf],
        conn: &Connection,
    ) -> anyhow::Result<()> {
        self.reload_from_paths(allow_paths, block_paths)?;
        match Self::merge_db_rules(conn) {
            Ok(db) => self.block.extend(db),
            Err(e) => tracing::warn!(error = %e, "load db dns_block rules skipped"),
        }
        match Self::merge_db_allow_rules(conn) {
            Ok(db) => self.allow.extend(db),
            Err(e) => tracing::warn!(error = %e, "load db dns_allow rules skipped"),
        }
        Ok(())
    }

    /// Evaluate: allowlist wins; then suffix / exact block match.
    pub fn decision(&self, domain: &str) -> FilterDecision {
        let d = normalize_domain(domain);
        if self.allow.contains(&d) {
            return FilterDecision::Allow;
        }
        if self.block.contains(&d) {
            return FilterDecision::Block;
        }
        for blocked in &self.block {
            if let Some(suffix) = blocked.strip_prefix("*.") {
                if d == suffix || d.ends_with(&format!(".{suffix}")) {
                    return FilterDecision::Block;
                }
            }
        }
        FilterDecision::Allow
    }
}

fn merge_file_into(set: &mut HashSet<String>, path: &PathBuf) -> anyhow::Result<()> {
    if !path.exists() {
        tracing::debug!(path = %path.display(), "list file missing; skip");
        return Ok(());
    }
    let text = std::fs::read_to_string(path)
        .map_err(|e| anyhow::anyhow!("read {}: {e}", path.display()))?;
    for line in text.lines() {
        let line = line.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        set.insert(normalize_domain(line));
    }
    Ok(())
}

fn normalize_domain(s: &str) -> String {
    let s = s.trim().trim_end_matches('.').to_lowercase();
    s
}
