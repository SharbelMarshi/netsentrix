//! WebSocket stream of DNS events (localhost).

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::ws::{Message, WebSocketUpgrade};
use axum::extract::State;
use axum::response::IntoResponse;
use futures_util::StreamExt;
use serde_json::json;

use crate::api::AppState;

pub async fn dns_events_ws(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(mut socket: axum::extract::ws::WebSocket, state: Arc<AppState>) {
    let mut rx = state.bus.subscribe_dns();
    loop {
        tokio::select! {
            incoming = socket.next() => {
                match incoming {
                    None => break,
                    Some(Ok(Message::Close(_))) => break,
                    Some(Ok(Message::Ping(p))) => {
                        let _ = socket.send(Message::Pong(p)).await;
                    }
                    Some(Ok(_)) => {}
                    Some(Err(_)) => break,
                }
            }
            ev = rx.recv() => {
                match ev {
                    Ok(ev) => {
                        let ts = SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .map(|d| d.as_millis() as i64)
                            .unwrap_or(0);
                        let ty = match ev.action.as_str() {
                            "blocked" | "blocked_forwarded" => "DNS_BLOCKED",
                            "allowed" => "DNS_ALLOWED",
                            _ => "DNS_QUERY",
                        };
                        let j = json!({
                            "type": ty,
                            "timestamp": ts,
                            "device_id": format!("ip:{}", ev.client_ip),
                            "payload": {
                                "domain": ev.domain,
                                "action": ev.action,
                                "client_ip": ev.client_ip,
                            }
                        });
                        if socket.send(Message::Text(j.to_string())).await.is_err() {
                            break;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => break,
                }
            }
        }
    }
}
