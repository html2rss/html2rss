//! Normalize rules mirroring `Html2rss::SST::Normalizer`.

use scraper::{ElementRef, Html, Node};

use super::ir::{IrAttrs, IrDocument, IrNode};

/// Hard ceiling for SST node allocations; beyond this we degrade.
pub const MAX_NODES: usize = 5_000;

/// Tags stripped entirely from the SST (must match `SST::Normalizer::STRIPPED_TAGS`).
pub const STRIPPED_TAGS: &[&str] = &["script", "style", "noscript", "iframe", "svg", "template"];

/// Kept when MAX_NODES forces semantic-tag-only degrade.
pub const SEMANTIC_DEGRADE_TAGS: &[&str] = &[
    "html", "body", "article", "section", "li", "tr", "div", "a", "h1", "h2", "h3", "h4", "h5",
    "h6", "time", "img", "p", "ul", "ol", "main",
];

/// Typed Attrs fields excluded from leftover raw.
pub const TYPED_ATTR_NAMES: &[&str] = &[
    "href", "src", "id", "class", "datetime", "itemprop", "style", "srcset", "type",
];

/// String form of ignored container tags for chrome.
pub const IGNORED_CONTAINER_TAGS: &[&str] = &["nav", "footer", "header", "svg", "script", "style"];

/// Parse HTML and build an IR SST document.
///
/// # Errors
///
/// Returns an error string when no nodes survive normalization.
pub fn normalize(html: &str) -> Result<IrDocument, String> {
    let parsed = Html::parse_document(html);
    let mut state = State::default();
    let root_el = resolve_root(&parsed);
    let root = normalize_element(root_el, "", 0, false, &mut state)
        .ok_or_else(|| "SST Normalizer produced an empty tree".to_string())?;

    Ok(IrDocument {
        root,
        node_count: state.node_count,
        degraded: state.degraded,
    })
}

#[derive(Default)]
struct State {
    node_count: usize,
    degraded: bool,
}

fn resolve_root<'a>(parsed: &'a Html) -> ElementRef<'a> {
    if let Some(html) = select_first(parsed, "html") {
        return html;
    }
    if let Some(body) = select_first(parsed, "body") {
        return body;
    }
    parsed
        .root_element()
        .children()
        .filter_map(ElementRef::wrap)
        .find(|el| el.value().name() != "html" || !stripped(el.value().name()))
        .unwrap_or_else(|| parsed.root_element())
}

fn select_first<'a>(parsed: &'a Html, selector: &str) -> Option<ElementRef<'a>> {
    let sel = scraper::Selector::parse(selector).ok()?;
    parsed.select(&sel).next()
}

fn stripped(tag: &str) -> bool {
    STRIPPED_TAGS.iter().any(|t| *t == tag)
}

fn semantic(tag: &str) -> bool {
    SEMANTIC_DEGRADE_TAGS.iter().any(|t| *t == tag)
}

fn ignored_container(tag: &str) -> bool {
    IGNORED_CONTAINER_TAGS.iter().any(|t| *t == tag)
}

fn normalize_element(
    el: ElementRef<'_>,
    path: &str,
    depth: usize,
    chrome: bool,
    state: &mut State,
) -> Option<IrNode> {
    let tag = el.value().name().to_ascii_lowercase();
    if stripped(&tag) {
        return None;
    }

    if state.node_count >= MAX_NODES && !state.degraded {
        state.degraded = true;
    }
    if state.degraded && !semantic(&tag) {
        return None;
    }

    state.node_count += 1;
    let tag_path = if path.is_empty() {
        format!("/{tag}")
    } else {
        format!("{path}/{tag}")
    };
    let chrome_here = chrome || ignored_container(&tag);
    let attrs = extract_attrs(el);
    let own_text = direct_text(el);

    let children: Vec<IrNode> = el
        .children()
        .filter_map(ElementRef::wrap)
        .filter_map(|child| normalize_element(child, &tag_path, depth + 1, chrome_here, state))
        .collect();

    // html5ever inserts an empty <head>; Nokogiri often omits it. Drop empty heads so
    // golden SST matches the portable Ruby Normalizer on typical documents.
    if tag == "head" && children.is_empty() && own_text.trim().is_empty() && attrs_empty(&attrs) {
        state.node_count = state.node_count.saturating_sub(1);
        return None;
    }

    Some(IrNode {
        name: tag,
        attrs,
        own_text,
        children,
        tag_path,
        depth,
        chrome: chrome_here,
    })
}

fn attrs_empty(attrs: &IrAttrs) -> bool {
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

fn direct_text(el: ElementRef<'_>) -> String {
    el.children()
        .filter_map(|node| match node.value() {
            Node::Text(text) => Some(text.to_string()),
            _ => None,
        })
        .collect()
}

fn extract_attrs(el: ElementRef<'_>) -> IrAttrs {
    let mut attrs = IrAttrs::default();
    for (name, value) in el.value().attrs() {
        let key = name.to_ascii_lowercase();
        match key.as_str() {
            "href" => attrs.href = blank_to_none(value),
            "src" => attrs.src = blank_to_none(value),
            "id" => attrs.id = blank_to_none(value),
            "class" => {
                attrs.class_names = value
                    .split_whitespace()
                    .filter(|t| !t.is_empty())
                    .map(str::to_string)
                    .collect();
            }
            "datetime" => attrs.datetime = blank_to_none(value),
            "itemprop" => attrs.itemprop = blank_to_none(value),
            "style" => attrs.style = blank_to_none(value),
            "srcset" => attrs.srcset = blank_to_none(value),
            "type" => attrs.r#type = blank_to_none(value),
            _ => {
                if keep_raw_attr(&key) && !typed_attr(&key) {
                    attrs.raw.insert(key, value.to_string());
                }
            }
        }
    }
    attrs
}

fn blank_to_none(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn typed_attr(name: &str) -> bool {
    TYPED_ATTR_NAMES.iter().any(|t| *t == name)
}

/// Mirror of `SST::Normalizer::RAW_ATTR_KEEP`.
pub fn keep_raw_attr(name: &str) -> bool {
    name.starts_with("data-")
        || name.starts_with("aria-")
        || matches!(
            name,
            "class"
                | "id"
                | "href"
                | "src"
                | "srcset"
                | "style"
                | "datetime"
                | "itemprop"
                | "type"
                | "category"
                | "categories"
                | "tag"
                | "tags"
                | "topic"
                | "topics"
                | "section"
                | "sections"
                | "label"
                | "labels"
                | "theme"
                | "themes"
                | "subject"
                | "subjects"
        )
}
