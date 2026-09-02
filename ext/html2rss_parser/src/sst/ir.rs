//! Intermediate SST representation built in Rust before Ruby hydrate.

use std::collections::HashMap;

/// Typed attributes matching `SST::Attrs` fields.
#[derive(Debug, Clone, Default)]
pub struct IrAttrs {
    pub href: Option<String>,
    pub src: Option<String>,
    pub id: Option<String>,
    pub class_names: Vec<String>,
    pub datetime: Option<String>,
    pub itemprop: Option<String>,
    pub style: Option<String>,
    pub srcset: Option<String>,
    pub r#type: Option<String>,
    pub raw: HashMap<String, String>,
}

/// One SST element after normalize.
#[derive(Debug, Clone)]
pub struct IrNode {
    pub name: String,
    pub attrs: IrAttrs,
    pub own_text: String,
    pub children: Vec<IrNode>,
    pub tag_path: String,
    pub depth: usize,
    pub chrome: bool,
}

/// Normalized tree ready for nested Hash IR → `SST::Hydrator`.
#[derive(Debug, Clone)]
pub struct IrDocument {
    pub root: IrNode,
    pub node_count: usize,
    pub degraded: bool,
}
