//! Wire/event DTOs for packet intelligence. Always compiled (no `pcap` / capture deps).
//! Used by the event bus, WebSocket, and optional sniffer pipeline.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PacketEvent {
    pub timestamp_ms: i64,
    pub src_ip: String,
    pub dst_ip: String,
    pub protocol: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub src_port: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dst_port: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub length: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub flags: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub raw_protocol_info: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityEvent {
    pub timestamp_ms: i64,
    pub src_ip: String,
    pub event_type: String,
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectionEvent {
    pub timestamp_ms: i64,
    pub severity: String,
    pub category: String,
    pub message: String,
    pub src_ip: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub related_ports: Option<Vec<u16>>,
}
