//! Internal pub/sub. **DNS queries** are live; packet/alert channels are reserved for future work.

use tokio::sync::broadcast;

use crate::events::models::DnsQueryEvent;
use crate::sniffer::models::{DetectionEvent, PacketEvent};

const CAPACITY: usize = 1024;

/// Fan-out for API WebSocket and other subscribers.
pub struct EventBus {
    dns_tx: broadcast::Sender<DnsQueryEvent>,
    packet_tx: broadcast::Sender<PacketEvent>,
    alert_tx: broadcast::Sender<DetectionEvent>,
}

impl EventBus {
    pub fn new() -> Self {
        let (dns_tx, _) = broadcast::channel(CAPACITY);
        let (packet_tx, _) = broadcast::channel(CAPACITY);
        let (alert_tx, _) = broadcast::channel(CAPACITY);
        Self {
            dns_tx,
            packet_tx,
            alert_tx,
        }
    }

    pub fn subscribe_dns(&self) -> broadcast::Receiver<DnsQueryEvent> {
        self.dns_tx.subscribe()
    }

    pub fn publish_dns(&self, ev: DnsQueryEvent) {
        let _ = self.dns_tx.send(ev);
    }

    pub fn subscribe_packet_activity(&self) -> broadcast::Receiver<PacketEvent> {
        self.packet_tx.subscribe()
    }

    pub fn publish_packet_activity(&self, ev: PacketEvent) {
        let _ = self.packet_tx.send(ev);
    }

    pub fn subscribe_alert_triggered(&self) -> broadcast::Receiver<DetectionEvent> {
        self.alert_tx.subscribe()
    }

    pub fn publish_alert_triggered(&self, ev: DetectionEvent) {
        let _ = self.alert_tx.send(ev);
    }
}
