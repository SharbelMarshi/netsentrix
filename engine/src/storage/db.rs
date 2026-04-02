use std::path::Path;

use anyhow::Context;
use rusqlite::Connection;

pub fn open(path: &Path) -> anyhow::Result<Connection> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).with_context(|| parent.display().to_string())?;
    }
    Connection::open(path).with_context(|| format!("open sqlite {}", path.display()))
}
