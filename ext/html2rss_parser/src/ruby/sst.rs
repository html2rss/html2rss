//! IR → direct Magnus `SST::{Attrs,Node,Index,Document}` (no nested Hash IR).

use magnus::{
    error::Error, exception::ExceptionClass, function, kwargs, prelude::*, value::Lazy, RArray,
    RClass, RHash, RModule, Ruby, Value,
};
use scraper::Html;

use crate::sst::ir::{IrAttrs, IrDocument, IrNode};
use crate::sst::normalize::{self, STRIPPED_TAGS};

static ATTRS: Lazy<RClass> = Lazy::new(|ruby| {
    ruby.eval("Html2rss::SST::Attrs")
        .expect("Html2rss::SST::Attrs must be loadable")
});
static NODE: Lazy<RClass> = Lazy::new(|ruby| {
    ruby.eval("Html2rss::SST::Node")
        .expect("Html2rss::SST::Node must be loadable")
});
static INDEX: Lazy<RClass> = Lazy::new(|ruby| {
    ruby.eval("Html2rss::SST::Index")
        .expect("Html2rss::SST::Index must be loadable")
});
static DOCUMENT: Lazy<RClass> = Lazy::new(|ruby| {
    ruby.eval("Html2rss::SST::Document")
        .expect("Html2rss::SST::Document must be loadable")
});
static EMPTY_TREE: Lazy<ExceptionClass> = Lazy::new(|ruby| {
    ruby.eval("Html2rss::SST::Normalizer::EmptyTree")
        .expect("Html2rss::SST::Normalizer::EmptyTree must be loadable")
});

/// Register SST helpers on `NativeEngine`.
pub fn register(ruby: &Ruby, native: RModule) -> Result<(), Error> {
    // Cache SST classes once at init — Path A must not `eval` per node.
    Lazy::force(&ATTRS, ruby);
    Lazy::force(&NODE, ruby);
    Lazy::force(&INDEX, ruby);
    Lazy::force(&DOCUMENT, ruby);
    Lazy::force(&EMPTY_TREE, ruby);

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

/// Build `SST::Document` from an HTML string (one parse + direct Magnus materialize).
pub fn to_sst_html(ruby: &Ruby, html: String) -> Result<Value, Error> {
    let ir = normalize::normalize(&html).map_err(|msg| empty_tree_error(ruby, &msg))?;
    materialize_document(ruby, &ir)
}

/// Build `SST::Document` from an already-parsed scraper tree (no serialize+reparse).
pub fn to_sst_from_html(ruby: &Ruby, html: &Html) -> Result<Value, Error> {
    let ir = normalize::normalize_from_html(html).map_err(|msg| empty_tree_error(ruby, &msg))?;
    materialize_document(ruby, &ir)
}

fn empty_tree_error(ruby: &Ruby, msg: &str) -> Error {
    let class = ruby.get_inner(&EMPTY_TREE);
    Error::new(class, msg.to_owned())
}

fn materialize_document(ruby: &Ruby, ir: &IrDocument) -> Result<Value, Error> {
    let parents = identity_hash(ruby)?;
    let depths = identity_hash(ruby)?;
    let ignored_chrome = identity_hash(ruby)?;

    let root = build_node(
        ruby,
        &ir.root,
        ruby.qnil().as_value(),
        &parents,
        &depths,
        &ignored_chrome,
    )?;

    let index: Value = ruby.get_inner(&INDEX).funcall(
        "new",
        (kwargs!(
            "root" => root,
            "parents" => parents,
            "depths" => depths,
            "ignored_chrome" => ignored_chrome
        ),),
    )?;

    ruby.get_inner(&DOCUMENT).funcall(
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
    let hash = ruby.hash_new();
    let _: Value = hash.funcall("compare_by_identity", ())?;
    Ok(hash)
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
    let children = ruby.ary_new_capa(ir.children.len());
    for child_ir in &ir.children {
        // Parent filled after this node exists (mirrors Hydrator pending → fix-up).
        let child = build_node(ruby, child_ir, nil, parents, depths, ignored_chrome)?;
        children.push(child)?;
    }

    let attrs = build_attrs(ruby, &ir.attrs)?;
    let node: Value = ruby.get_inner(&NODE).funcall(
        "build",
        (kwargs!(
            "name" => ir.name.as_str(),
            "attrs" => attrs,
            "own_text" => ir.own_text.as_str(),
            "children" => children,
            "tag_path" => ir.tag_path.as_str()
        ),),
    )?;

    parents.aset(node, parent)?;
    depths.aset(node, ir.depth as i64)?;
    ignored_chrome.aset(node, ir.chrome)?;

    let len = children.len() as isize;
    for i in 0..len {
        let child: Value = children.entry(i)?;
        parents.aset(child, node)?;
    }

    Ok(node)
}

fn build_attrs(ruby: &Ruby, attrs: &IrAttrs) -> Result<Value, Error> {
    if attrs_blank(attrs) {
        return ruby.get_inner(&ATTRS).funcall("empty", ());
    }

    let class_names = ruby.ary_new_capa(attrs.class_names.len());
    for name in &attrs.class_names {
        class_names.push(name.as_str())?;
    }

    let raw = ruby.hash_new();
    for (k, v) in &attrs.raw {
        raw.aset(k.as_str(), v.as_str())?;
    }

    ruby.get_inner(&ATTRS).funcall(
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

fn attrs_blank(attrs: &IrAttrs) -> bool {
    attrs.href.is_none()
        && attrs.src.is_none()
        && attrs.id.is_none()
        && attrs.class_names.is_empty()
        && attrs.datetime.is_none()
        && attrs.itemprop.is_none()
        && attrs.style.is_none()
        && attrs.srcset.is_none()
        && attrs.r#type.is_none()
        && attrs.raw.is_empty()
}
