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
