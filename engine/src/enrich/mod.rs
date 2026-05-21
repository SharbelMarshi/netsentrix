//! Offline enrichment (Phase 8). GeoIP/ASN `.mmdb` paths can be added to config later; today the app
//! consumes **deterministic domain explanations** from the classifier via API (`/insights/daily`).

pub use crate::alerts::classification::explain_domain;
