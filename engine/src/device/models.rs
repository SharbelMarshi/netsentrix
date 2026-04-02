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
}
