//! Normalize rules mirroring `Html2rss::SST::Normalizer` (constants sync in Phase 2).

/// Hard ceiling for SST node allocations; beyond this we degrade.
#[allow(dead_code)] // wired in Phase 2
pub const MAX_NODES: usize = 5_000;

/// Tags stripped entirely from the SST (must match `SST::Normalizer::STRIPPED_TAGS`).
#[allow(dead_code)] // wired in Phase 2
pub const STRIPPED_TAGS: &[&str] = &["script", "style", "noscript", "iframe", "svg", "template"];
