use axum::body::Body;
use axum::http::{header, Request, StatusCode};
use axum::middleware::Next;
use axum::response::Response;
use rand::Rng;

use crate::api::AppState;
use crate::system::paths;

pub fn load_or_create_token() -> anyhow::Result<String> {
    let path = paths::token_path();
    if path.exists() {
        let s = std::fs::read_to_string(&path)?;
        let t = s.trim();
        if !t.is_empty() {
            return Ok(t.to_string());
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let b: [u8; 32] = rand::thread_rng().gen();
    let token = hex::encode(b);
    std::fs::write(&path, &token)?;
    tracing::info!(path = %path.display(), "wrote API token");
    Ok(token)
}

/// Resolved token path (same rules as [`crate::system::paths::token_path`]).
pub fn token_path() -> std::path::PathBuf {
    paths::token_path()
}

/// Require `Authorization: Bearer <token>` for every request on the authed router
/// (settings POST, reload, rules, device rename, engine no-ops, etc.).
pub async fn require_bearer_middleware(
    axum::extract::State(state): axum::extract::State<std::sync::Arc<AppState>>,
    req: Request<Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    let expected = format!("Bearer {}", state.api_token);
    let got = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok());
    match got {
        Some(g) if g == expected => Ok(next.run(req).await),
        _ => Err(StatusCode::UNAUTHORIZED),
    }
}
