//! Optional live capture (libpcap). DNS-only builds omit `sniffer` feature.

pub mod models;

#[cfg(feature = "sniffer")]
pub mod capture;
#[cfg(feature = "sniffer")]
pub mod normalize;
#[cfg(feature = "sniffer")]
pub mod pipeline;

#[cfg(feature = "sniffer")]
pub fn spawn_sniffer_thread(
    bus: std::sync::Arc<crate::events::bus::EventBus>,
    db: std::sync::Arc<std::sync::Mutex<rusqlite::Connection>>,
    shutdown: std::sync::Arc<std::sync::atomic::AtomicBool>,
) -> std::thread::JoinHandle<()> {
    std::thread::Builder::new()
        .name("netsentrix-sniffer".to_string())
        .spawn(move || {
            if let Err(e) = pipeline::run_sniffer_pipeline(bus, db, shutdown) {
                tracing::error!(error = %e, "sniffer pipeline exited");
            }
        })
        .expect("spawn sniffer thread")
}
