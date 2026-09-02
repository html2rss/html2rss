//! IR → nested Ruby Hash → `SST::Hydrator.call` (one FFI hydrate).

use magnus::{
    error::Error, function, kwargs, prelude::*, RArray, RClass, RHash, RModule, Ruby, Value,
};
use scraper::Html;

use crate::sst::ir::{IrAttrs, IrDocument, IrNode};
use crate::sst::normalize::{self, STRIPPED_TAGS};

/// Register SST helpers on `NativeEngine`.
pub fn register(ruby: &Ruby, native: RModule) -> Result<(), Error> {
    // Warm Hydrator so first `to_sst` does not pay a missing-constant path.
    let _: RClass = ruby.eval("Html2rss::SST::Hydrator")?;

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

/// Build `SST::Document` from an HTML string (one parse + one hydrate).
pub fn to_sst_html(ruby: &Ruby, html: String) -> Result<Value, Error> {
    let ir = normalize::normalize(&html).map_err(|msg| empty_tree_error(ruby, &msg))?;
    hydrate_document(ruby, &ir)
}

/// Build `SST::Document` from an already-parsed scraper tree (no serialize+reparse).
pub fn to_sst_from_html(ruby: &Ruby, html: &Html) -> Result<Value, Error> {
    let ir = normalize::normalize_from_html(html).map_err(|msg| empty_tree_error(ruby, &msg))?;
    hydrate_document(ruby, &ir)
}

fn empty_tree_error(ruby: &Ruby, msg: &str) -> Error {
    let owned = msg.to_owned();
    match ruby.eval::<magnus::exception::ExceptionClass>("Html2rss::SST::Normalizer::EmptyTree") {
        Ok(class) => Error::new(class, owned),
        Err(_) => Error::new(ruby.exception_arg_error(), owned),
    }
}

fn hydrate_document(ruby: &Ruby, ir: &IrDocument) -> Result<Value, Error> {
    let root_ir = ir_node_to_hash(ruby, &ir.root)?;
    let hydrator = ruby.eval::<RClass>("Html2rss::SST::Hydrator")?;
    hydrator.funcall(
        "call",
        (
            root_ir,
            kwargs!(
                "node_count" => ir.node_count as i64,
                "degraded" => ir.degraded
            ),
        ),
    )
}

fn ir_node_to_hash(ruby: &Ruby, ir: &IrNode) -> Result<RHash, Error> {
    let children = ruby.ary_new_capa(ir.children.len());
    for child in &ir.children {
        children.push(ir_node_to_hash(ruby, child)?)?;
    }

    let hash = ruby.hash_new();
    hash.aset("name", ir.name.as_str())?;
    hash.aset("attrs", ir_attrs_to_hash(ruby, &ir.attrs)?)?;
    hash.aset("own_text", ir.own_text.as_str())?;
    hash.aset("children", children)?;
    hash.aset("tag_path", ir.tag_path.as_str())?;
    hash.aset("depth", ir.depth as i64)?;
    hash.aset("chrome", ir.chrome)?;
    Ok(hash)
}

fn ir_attrs_to_hash(ruby: &Ruby, attrs: &IrAttrs) -> Result<RHash, Error> {
    let class_names = ruby.ary_new_capa(attrs.class_names.len());
    for name in &attrs.class_names {
        class_names.push(name.as_str())?;
    }

    let raw = ruby.hash_new();
    for (k, v) in &attrs.raw {
        raw.aset(k.as_str(), v.as_str())?;
    }

    let hash = ruby.hash_new();
    hash.aset("href", attrs.href.as_deref())?;
    hash.aset("src", attrs.src.as_deref())?;
    hash.aset("id", attrs.id.as_deref())?;
    hash.aset("class_names", class_names)?;
    hash.aset("datetime", attrs.datetime.as_deref())?;
    hash.aset("itemprop", attrs.itemprop.as_deref())?;
    hash.aset("style", attrs.style.as_deref())?;
    hash.aset("srcset", attrs.srcset.as_deref())?;
    hash.aset("type", attrs.r#type.as_deref())?;
    hash.aset("raw", raw)?;
    Ok(hash)
}
