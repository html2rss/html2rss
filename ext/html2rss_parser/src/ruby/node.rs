//! NativeEngine::Node — attr / CSS / text ducks over a NodeId.

use std::cell::RefCell;
use std::rc::Rc;

use ego_tree::NodeId;
use magnus::{error::Error, method, prelude::*, RArray, RClass, RModule, Ruby, Value};
use scraper::{ElementRef, Node as DomNode, Selector};

use super::document::{DocInner, NativeDocument};

/// Ruby `Html2rss::Html::NativeEngine::Node`.
#[magnus::wrap(class = "Html2rss::Html::NativeEngine::Node", free_immediately, size)]
#[derive(Clone)]
pub struct NativeNode {
    pub(crate) inner: Rc<RefCell<DocInner>>,
    pub(crate) id: NodeId,
}

unsafe impl Send for NativeNode {}

/// Attribute duck returned from `attribute_nodes` (name + value).
#[magnus::wrap(class = "Html2rss::Html::NativeEngine::Attr", free_immediately, size)]
struct NativeAttr {
    name: String,
    value: String,
}

unsafe impl Send for NativeAttr {}

/// Register Node / Attr classes.
pub fn register(ruby: &Ruby, native: RModule) -> Result<(), Error> {
    let attr = native.define_class("Attr", ruby.class_object())?;
    attr.define_method("name", method!(NativeAttr::rb_name, 0))?;
    attr.define_method("value", method!(NativeAttr::rb_value, 0))?;

    let class = native.define_class("Node", ruby.class_object())?;
    class.define_method("css", method!(NativeNode::rb_css, 1))?;
    class.define_method("at_css", method!(NativeNode::rb_at_css, 1))?;
    class.define_method("name", method!(NativeNode::rb_name, 0))?;
    class.define_method("[]", method!(NativeNode::rb_attr, 1))?;
    class.define_method("text", method!(NativeNode::rb_text, 0))?;
    class.define_method("to_html", method!(NativeNode::rb_to_html, 0))?;
    class.define_method("children", method!(NativeNode::rb_children, 0))?;
    class.define_method("element_children", method!(NativeNode::rb_element_children, 0))?;
    class.define_method("element?", method!(NativeNode::rb_element_p, 0))?;
    class.define_method("text?", method!(NativeNode::rb_text_p, 0))?;
    class.define_method("comment?", method!(NativeNode::rb_comment_p, 0))?;
    class.define_method("parent", method!(NativeNode::rb_parent, 0))?;
    class.define_method("attribute_nodes", method!(NativeNode::rb_attribute_nodes, 0))?;
    class.define_method("remove", method!(NativeNode::rb_remove, 0))?;
    class.define_method("descendant_texts", method!(NativeNode::rb_descendant_texts, 0))?;
    Ok(())
}

impl NativeAttr {
    fn rb_name(&self) -> &str {
        &self.name
    }

    fn rb_value(&self) -> &str {
        &self.value
    }
}

impl NativeNode {
    fn element<'a>(&self, borrow: &'a DocInner) -> Option<ElementRef<'a>> {
        if borrow.removed.contains(&self.id) {
            return None;
        }
        borrow.html.tree.get(self.id).and_then(ElementRef::wrap)
    }

    pub(crate) fn rb_css(ruby: &Ruby, rb_self: &Self, selector: String) -> Result<RArray, Error> {
        let sel = Selector::parse(&selector).map_err(|e| {
            Error::new(
                ruby.exception_arg_error(),
                format!("invalid CSS selector: {e}"),
            )
        })?;
        let borrow = rb_self.inner.borrow();
        let arr = ruby.ary_new();
        let Some(el) = rb_self.element(&borrow) else {
            return Ok(arr);
        };
        for child in el.select(&sel) {
            if !borrow.removed.contains(&child.id()) {
                arr.push(NativeNode {
                    inner: Rc::clone(&rb_self.inner),
                    id: child.id(),
                })?;
            }
        }
        Ok(arr)
    }

    pub(crate) fn rb_at_css(ruby: &Ruby, rb_self: &Self, selector: String) -> Result<Option<NativeNode>, Error> {
        let sel = Selector::parse(&selector).map_err(|e| {
            Error::new(
                ruby.exception_arg_error(),
                format!("invalid CSS selector: {e}"),
            )
        })?;
        let borrow = rb_self.inner.borrow();
        let Some(el) = rb_self.element(&borrow) else {
            return Ok(None);
        };
        Ok(el
            .select(&sel)
            .find(|c| !borrow.removed.contains(&c.id()))
            .map(|c| NativeNode {
                inner: Rc::clone(&rb_self.inner),
                id: c.id(),
            }))
    }

    fn rb_name(&self) -> String {
        let borrow = self.inner.borrow();
        match borrow.html.tree.get(self.id).map(|n| n.value()) {
            Some(DomNode::Element(el)) => el.name().to_string(),
            Some(DomNode::Text(_)) => "#text".to_string(),
            Some(DomNode::Comment(_)) => "#comment".to_string(),
            _ => "#document".to_string(),
        }
    }

    fn rb_attr(&self, name: String) -> Option<String> {
        let borrow = self.inner.borrow();
        self.element(&borrow)
            .and_then(|el| el.value().attr(&name).map(str::to_string))
    }

    fn rb_text(&self) -> String {
        let borrow = self.inner.borrow();
        match borrow.html.tree.get(self.id).map(|n| n.value()) {
            Some(DomNode::Text(t)) => t.to_string(),
            Some(DomNode::Element(_)) => self
                .element(&borrow)
                .map(|el| el.text().collect::<String>())
                .unwrap_or_default(),
            _ => String::new(),
        }
    }

    fn rb_to_html(&self) -> String {
        let borrow = self.inner.borrow();
        self.element(&borrow)
            .map(|el| el.html())
            .unwrap_or_default()
    }

    pub(crate) fn rb_children(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let borrow = rb_self.inner.borrow();
        let arr = ruby.ary_new();
        let Some(node) = borrow.html.tree.get(rb_self.id) else {
            return Ok(arr);
        };
        for child in node.children() {
            if borrow.removed.contains(&child.id()) {
                continue;
            }
            arr.push(NativeNode {
                inner: Rc::clone(&rb_self.inner),
                id: child.id(),
            })?;
        }
        Ok(arr)
    }

    pub(crate) fn rb_element_children(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let borrow = rb_self.inner.borrow();
        let arr = ruby.ary_new();
        let Some(el) = rb_self.element(&borrow) else {
            return Ok(arr);
        };
        for child in el.children().filter_map(ElementRef::wrap) {
            if borrow.removed.contains(&child.id()) {
                continue;
            }
            arr.push(NativeNode {
                inner: Rc::clone(&rb_self.inner),
                id: child.id(),
            })?;
        }
        Ok(arr)
    }

    fn rb_element_p(&self) -> bool {
        let borrow = self.inner.borrow();
        matches!(
            borrow.html.tree.get(self.id).map(|n| n.value()),
            Some(DomNode::Element(_))
        )
    }

    fn rb_text_p(&self) -> bool {
        let borrow = self.inner.borrow();
        matches!(
            borrow.html.tree.get(self.id).map(|n| n.value()),
            Some(DomNode::Text(_))
        )
    }

    fn rb_comment_p(&self) -> bool {
        let borrow = self.inner.borrow();
        matches!(
            borrow.html.tree.get(self.id).map(|n| n.value()),
            Some(DomNode::Comment(_))
        )
    }

    fn rb_parent(&self) -> Option<NativeNode> {
        let borrow = self.inner.borrow();
        borrow.html.tree.get(self.id).and_then(|n| {
            n.parent().map(|p| NativeNode {
                inner: Rc::clone(&self.inner),
                id: p.id(),
            })
        })
    }

    pub(crate) fn rb_attribute_nodes(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let borrow = rb_self.inner.borrow();
        let arr = ruby.ary_new();
        let Some(el) = rb_self.element(&borrow) else {
            return Ok(arr);
        };
        for (name, value) in el.value().attrs() {
            arr.push(NativeAttr {
                name: name.to_string(),
                value: value.to_string(),
            })?;
        }
        Ok(arr)
    }

    fn rb_remove(&self) {
        self.inner.borrow_mut().removed.insert(self.id);
    }

    pub(crate) fn rb_descendant_texts(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let borrow = rb_self.inner.borrow();
        let arr = ruby.ary_new();
        let Some(node) = borrow.html.tree.get(rb_self.id) else {
            return Ok(arr);
        };
        for desc in node.descendants() {
            if borrow.removed.contains(&desc.id()) {
                continue;
            }
            if matches!(desc.value(), DomNode::Text(_)) {
                arr.push(NativeNode {
                    inner: Rc::clone(&rb_self.inner),
                    id: desc.id(),
                })?;
            }
        }
        Ok(arr)
    }
}

/// Keep NativeDocument import used for type visibility in wrap class path.
#[allow(dead_code)]
fn _doc_class_anchor() -> Option<RClass> {
    let _ = std::any::type_name::<NativeDocument>();
    None
}
