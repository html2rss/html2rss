//! NativeEngine::Document — owned scraper Html + CSS ducks.

use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

use ego_tree::NodeId;
use magnus::{error::Error, function, method, prelude::*, RArray, RModule, Ruby, Value};
use scraper::{Html, Node as DomNode, Selector};

use super::node::NativeNode;

pub(crate) struct DocInner {
    pub html: Html,
    pub removed: HashSet<NodeId>,
}

/// Ruby `Html2rss::Html::NativeEngine::Document`.
#[magnus::wrap(class = "Html2rss::Html::NativeEngine::Document", free_immediately, size)]
pub struct NativeDocument {
    pub(crate) inner: Rc<RefCell<DocInner>>,
}

// Ruby GVL: TypedData values are not moved across threads.
unsafe impl Send for NativeDocument {}

/// Register Document class methods.
pub fn register(ruby: &Ruby, native: RModule) -> Result<(), Error> {
    let class = native.define_class("Document", ruby.class_object())?;
    class.define_singleton_method("parse", function!(NativeDocument::rb_parse, 1))?;
    class.define_singleton_method("fragment", function!(NativeDocument::rb_fragment, 1))?;
    class.define_method("css", method!(NativeDocument::rb_css, 1))?;
    class.define_method("at_css", method!(NativeDocument::rb_at_css, 1))?;
    class.define_method("name", method!(NativeDocument::rb_name, 0))?;
    class.define_method("[]", method!(NativeDocument::rb_attr, 1))?;
    class.define_method("attr", method!(NativeDocument::rb_attr, 1))?;
    class.define_method("text", method!(NativeDocument::rb_text, 0))?;
    class.define_method("to_html", method!(NativeDocument::rb_to_html, 0))?;
    class.define_method("to_sst", method!(NativeDocument::rb_to_sst, 0))?;
    class.define_method("children", method!(NativeDocument::rb_children, 0))?;
    class.define_method("element_children", method!(NativeDocument::rb_element_children, 0))?;
    class.define_method("element?", method!(NativeDocument::rb_element_p, 0))?;
    class.define_method("text?", method!(NativeDocument::rb_text_p, 0))?;
    class.define_method("comment?", method!(NativeDocument::rb_comment_p, 0))?;
    class.define_method("document?", method!(NativeDocument::rb_document_p, 0))?;
    class.define_method("parent", method!(NativeDocument::rb_parent, 0))?;
    class.define_method("attribute_nodes", method!(NativeDocument::rb_attribute_nodes, 0))?;
    class.define_method("remove", method!(NativeDocument::rb_remove, 0))?;
    class.define_method("traverse", method!(NativeDocument::rb_traverse, 0))?;
    class.define_method("remove_comments!", method!(NativeDocument::rb_remove_comments, 0))?;
    class.define_method("html_document?", method!(NativeDocument::rb_html_document_p, 0))?;
    class.define_method("descendant_texts", method!(NativeDocument::rb_descendant_texts, 0))?;
    Ok(())
}

impl NativeDocument {
    pub(crate) fn from_html(html: Html) -> Self {
        Self {
            inner: Rc::new(RefCell::new(DocInner {
                html,
                removed: HashSet::new(),
            })),
        }
    }

    fn wrap_id(&self, id: NodeId) -> NativeNode {
        NativeNode {
            inner: Rc::clone(&self.inner),
            id,
        }
    }

    fn root_node(&self) -> NativeNode {
        let id = self.inner.borrow().html.root_element().id();
        self.wrap_id(id)
    }

    fn rb_parse(html: String) -> Self {
        Self::from_html(Html::parse_document(&html))
    }

    fn rb_fragment(html: String) -> Self {
        Self::from_html(Html::parse_fragment(&html))
    }

    fn rb_css(ruby: &Ruby, rb_self: &Self, selector: String) -> Result<RArray, Error> {
        let sel = parse_selector(ruby, &selector)?;
        let borrow = rb_self.inner.borrow();
        let arr = ruby.ary_new();
        for el in borrow.html.select(&sel) {
            if !borrow.removed.contains(&el.id()) {
                arr.push(rb_self.wrap_id(el.id()))?;
            }
        }
        Ok(arr)
    }

    fn rb_at_css(ruby: &Ruby, rb_self: &Self, selector: String) -> Result<Option<NativeNode>, Error> {
        let sel = parse_selector(ruby, &selector)?;
        let borrow = rb_self.inner.borrow();
        Ok(borrow
            .html
            .select(&sel)
            .find(|el| !borrow.removed.contains(&el.id()))
            .map(|el| rb_self.wrap_id(el.id())))
    }

    fn rb_name(&self) -> String {
        self.inner
            .borrow()
            .html
            .root_element()
            .value()
            .name()
            .to_string()
    }

    fn rb_attr(&self, name: String) -> Option<String> {
        self.inner
            .borrow()
            .html
            .root_element()
            .value()
            .attr(&name)
            .map(str::to_string)
    }

    fn rb_text(&self) -> String {
        self.inner.borrow().html.root_element().text().collect()
    }

    fn rb_to_html(&self) -> String {
        // Soft-deleted element ids are CSS-only; serialize reflects the live scraper tree.
        // Comments are detached in remove_comments!, so they do not reappear here.
        self.inner.borrow().html.html()
    }

    fn rb_to_sst(ruby: &Ruby, rb_self: &Self) -> Result<Value, Error> {
        let borrow = rb_self.inner.borrow();
        super::sst::to_sst_from_html(ruby, &borrow.html)
    }

    fn rb_children(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        NativeNode::rb_children(ruby, &rb_self.root_node())
    }

    fn rb_element_children(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        NativeNode::rb_element_children(ruby, &rb_self.root_node())
    }

    fn rb_element_p(&self) -> bool {
        true
    }

    fn rb_text_p(&self) -> bool {
        false
    }

    fn rb_comment_p(&self) -> bool {
        false
    }

    fn rb_document_p(&self) -> bool {
        true
    }

    fn rb_parent(&self) -> Option<NativeNode> {
        None
    }

    fn rb_attribute_nodes(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        NativeNode::rb_attribute_nodes(ruby, &rb_self.root_node())
    }

    fn rb_remove(&self) {}

    fn rb_traverse(ruby: &Ruby, rb_self: &Self) -> Result<(), Error> {
        let ids: Vec<NodeId> = {
            let borrow = rb_self.inner.borrow();
            borrow
                .html
                .root_element()
                .descendants()
                .map(|n| n.id())
                .filter(|id| !borrow.removed.contains(id))
                .collect()
        };
        for id in ids {
            let _: Value = ruby.yield_value(rb_self.wrap_id(id))?;
        }
        Ok(())
    }

    fn rb_remove_comments(&self) {
        // Detach for real — soft-delete HashSet never affected serialize/SST.
        let mut borrow = self.inner.borrow_mut();
        let ids: Vec<NodeId> = borrow
            .html
            .tree
            .nodes()
            .filter_map(|n| match n.value() {
                DomNode::Comment(_) => Some(n.id()),
                _ => None,
            })
            .collect();
        for id in ids {
            if let Some(mut node) = borrow.html.tree.get_mut(id) {
                node.detach();
            }
        }
    }

    fn rb_html_document_p(&self) -> bool {
        true
    }

    fn rb_descendant_texts(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        NativeNode::rb_descendant_texts(ruby, &rb_self.root_node())
    }
}

fn parse_selector(ruby: &Ruby, selector: &str) -> Result<Selector, Error> {
    Selector::parse(selector).map_err(|e| {
        Error::new(
            ruby.exception_arg_error(),
            format!("invalid CSS selector: {e}"),
        )
    })
}
