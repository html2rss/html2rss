//! IR → Ruby `SST::{Attrs,Node,Index,Document}`.

use magnus::{
    error::Error, function, kwargs, prelude::*, RArray, RClass, RHash, RModule, Ruby, Value,
};

use crate::sst::ir::{IrAttrs, IrDocument, IrNode};
use crate::sst::normalize::{self, STRIPPED_TAGS};

/// Register SST helpers on `NativeEngine`.
pub fn register(_ruby: &Ruby, native: RModule) -> Result<(), Error> {
    native.define_singleton_method("to_sst", function!(to_sst, 1))?;
    native.define_singleton_method("stripped_tags", function!(stripped_tags, 0))?;
    native.define_singleton_method("max_nodes", function!(max_nodes, 0))?;
    native.define_singleton_method("semantic_degrade_tags", function!(semantic_degrade_tags, 0))?;
    Ok(())
}

fn stripped_tags(ruby: &Ruby) -> Result<RArray, Error> {
    let arr = ruby.ary_new_capa(STRIPPED_TAGS.len());
    for tag in STRIPPED_TAGS {
        arr.push(*tag)?;
    }
    Ok(arr)
}

fn max_nodes(_ruby: &Ruby) -> i64 {
    normalize::MAX_NODES as i64
}

fn semantic_degrade_tags(ruby: &Ruby) -> Result<RArray, Error> {
    let arr = ruby.ary_new_capa(normalize::SEMANTIC_DEGRADE_TAGS.len());
    for tag in normalize::SEMANTIC_DEGRADE_TAGS {
        arr.push(*tag)?;
    }
    Ok(arr)
}

fn to_sst(ruby: &Ruby, html: String) -> Result<Value, Error> {
    to_sst_html(ruby, html)
}

/// Build `SST::Document` from an HTML string (shared by `to_sst` and `Document#to_sst`).
pub fn to_sst_html(ruby: &Ruby, html: String) -> Result<Value, Error> {
    let ir = normalize::normalize(&html).map_err(|msg| empty_tree_error(ruby, &msg))?;
    build_document(ruby, &ir)
}

fn empty_tree_error(ruby: &Ruby, msg: &str) -> Error {
    let owned = msg.to_owned();
    match ruby.eval::<magnus::exception::ExceptionClass>("Html2rss::SST::Normalizer::EmptyTree") {
        Ok(class) => Error::new(class, owned),
        Err(_) => Error::new(ruby.exception_arg_error(), owned),
    }
}

fn build_document(ruby: &Ruby, ir: &IrDocument) -> Result<Value, Error> {
    let parents = identity_hash(ruby)?;
    let depths = identity_hash(ruby)?;
    let ignored_chrome = identity_hash(ruby)?;
    let nil = ruby.qnil().as_value();

    let root = build_node(ruby, &ir.root, nil, &parents, &depths, &ignored_chrome)?;

    let index_class = ruby.eval::<RClass>("Html2rss::SST::Index")?;
    let index: Value = index_class.funcall(
        "new",
        (kwargs!(
            "root" => root,
            "parents" => parents,
            "depths" => depths,
            "ignored_chrome" => ignored_chrome
        ),),
    )?;

    let doc_class = ruby.eval::<RClass>("Html2rss::SST::Document")?;
    doc_class.funcall(
        "build",
        (kwargs!(
            "root" => root,
            "index" => index,
            "degraded" => ir.degraded,
            "node_count" => ir.node_count as i64
        ),),
    )
}

fn identity_hash(ruby: &Ruby) -> Result<RHash, Error> {
    ruby.eval::<RHash>("{}.compare_by_identity")
}

fn build_node(
    ruby: &Ruby,
    ir: &IrNode,
    parent: Value,
    parents: &RHash,
    depths: &RHash,
    ignored_chrome: &RHash,
) -> Result<Value, Error> {
    let nil = ruby.qnil().as_value();
    let mut child_nodes = Vec::with_capacity(ir.children.len());
    for child in &ir.children {
        let child_node = build_node(ruby, child, nil, parents, depths, ignored_chrome)?;
        child_nodes.push(child_node);
    }

    let attrs = build_attrs(ruby, &ir.attrs)?;
    let children_ary = ruby.ary_new_capa(child_nodes.len());
    for child in &child_nodes {
        children_ary.push(*child)?;
    }

    let node_class = ruby.eval::<RClass>("Html2rss::SST::Node")?;
    let node: Value = node_class.funcall(
        "build",
        (kwargs!(
            "name" => ir.name.as_str(),
            "attrs" => attrs,
            "own_text" => ir.own_text.as_str(),
            "children" => children_ary,
            "tag_path" => ir.tag_path.as_str()
        ),),
    )?;

    parents.aset(node, parent)?;
    depths.aset(node, ir.depth as i64)?;
    ignored_chrome.aset(node, ir.chrome)?;

    for child in &child_nodes {
        parents.aset(*child, node)?;
    }

    Ok(node)
}

fn build_attrs(ruby: &Ruby, attrs: &IrAttrs) -> Result<Value, Error> {
    let class_names = ruby.ary_new_capa(attrs.class_names.len());
    for name in &attrs.class_names {
        class_names.push(name.as_str())?;
    }

    let raw = ruby.hash_new();
    for (k, v) in &attrs.raw {
        raw.aset(k.as_str(), v.as_str())?;
    }

    let attrs_class = ruby.eval::<RClass>("Html2rss::SST::Attrs")?;
    attrs_class.funcall(
        "build",
        (kwargs!(
            "href" => attrs.href.as_deref(),
            "src" => attrs.src.as_deref(),
            "id" => attrs.id.as_deref(),
            "class_names" => class_names,
            "datetime" => attrs.datetime.as_deref(),
            "itemprop" => attrs.itemprop.as_deref(),
            "style" => attrs.style.as_deref(),
            "srcset" => attrs.srcset.as_deref(),
            "type" => attrs.r#type.as_deref(),
            "raw" => raw
        ),),
    )
}
