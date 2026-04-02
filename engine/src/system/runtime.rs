//! Process-level status for the API (`engine_status` on `/health`).
//!
//! **Operational note:** The engine transitions to [`EngineStatus::Running`] when the API task and
//! DNS worker tasks are spawned — **before** DNS sockets necessarily finish binding. Treat
//! `dns_udp_bound`, `dns_tcp_bound`, and `dns_*_last_error` as the source of truth for listeners.
//! [`EngineStatus::Error`] is set when **UDP** DNS bind fails (TCP-only failure does not flip this).

#[derive(Debug, Clone)]
pub enum EngineStatus {
    Starting,
    Running,
    /// Reserved for explicit lifecycle (pause uses `dns_paused`, not this).
    #[allow(dead_code)]
    Stopped,
    /// Critical failure (e.g. DNS UDP bind failed).
    Error,
}

impl EngineStatus {
    pub fn starting() -> Self {
        Self::Starting
    }

    pub fn running() -> Self {
        Self::Running
    }

    pub fn error() -> Self {
        Self::Error
    }

    pub fn to_api_string(&self) -> String {
        match self {
            EngineStatus::Starting => "starting".to_string(),
            EngineStatus::Running => "running".to_string(),
            EngineStatus::Stopped => "stopped".to_string(),
            EngineStatus::Error => "error".to_string(),
        }
    }
}
