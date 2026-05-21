#[derive(Debug, Clone)]
pub struct DeviceRow {
    pub id: String,
    pub ip_address: String,
    pub mac_address: Option<String>,
    pub hostname: Option<String>,
    pub vendor: Option<String>,
    pub name: Option<String>,
    pub first_seen: Option<i64>,
    pub last_seen: Option<i64>,
    pub is_active: bool,
    pub is_protected: bool,
    /// `normal` | `restricted` | `paused` | `blocked`
    pub dns_policy: String,
    /// Comma-separated tags (FG4), e.g. `Child,Guest`.
    pub tags: String,
}
