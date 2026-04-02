//! Minimal DNS-driven alerts (thresholds + cooldowns). Not a full detection product.

mod classification;
mod minimal;

pub use minimal::evaluate_after_query;
