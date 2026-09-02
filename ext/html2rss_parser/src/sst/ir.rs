//! Intermediate SST representation built in Rust before Magnus mapping.

/// Placeholder IR root (Phase 2 fills this in).
#[derive(Debug, Clone)]
#[allow(dead_code)] // wired in Phase 2
pub struct IrDocument {
    /// Number of SST nodes after normalize.
    pub node_count: usize,
    /// Whether MAX_NODES forced semantic-tag-only degrade.
    pub degraded: bool,
}
