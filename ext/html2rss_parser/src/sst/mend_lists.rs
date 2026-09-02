//! Mend html5ever adoption-agency splits so list SST matches libxml/Nokogiri nesting.
//!
//! Malformed carousels often omit `</a></li>` for early items. libxml nests subsequent
//! `li`s inside the open `a` and keeps that stack open so later sections share a long
//! `tag_path` prefix; html5ever closes into sibling `li`s. This pass:
//! 1. Rebuilds the nested `li`/`a` chain (with nested `li` under the content `div`).
//! 2. Bottom-up, reparents following siblings into the innermost open `a` (not at
//!    `body`/`html`, so footer stays out) so list-strategy path frequencies align.

use super::ir::IrNode;
use super::normalize::ignored_container;

/// Rewrite adoption-agency-split lists under `root`, then refresh depth/tag_path/chrome.
pub fn mend_unclosed_anchor_lists(root: &mut IrNode) {
    mend_chains(root);
    blackhole_following_siblings(root);
    let chrome = root.chrome;
    reindex(root, "", 0, chrome);
}

fn mend_chains(node: &mut IrNode) {
    for child in &mut node.children {
        mend_chains(child);
    }
    if matches!(node.name.as_str(), "ul" | "ol") {
        mend_list_chain(node);
    }
}

fn mend_list_chain(list: &mut IrNode) {
    if list.children.len() < 2 || !list.children.iter().all(|c| c.name == "li") {
        return;
    }
    if !is_split_anchor_li(&list.children[0]) {
        return;
    }

    let mut lis = std::mem::take(&mut list.children);
    let mut nested: Option<IrNode> = None;
    while let Some(mut li) = lis.pop() {
        merge_split_anchor_li(&mut li);
        if let Some(inner) = nested.take() {
            nest_li_like_libxml(&mut li, inner);
        }
        nested = Some(li);
    }
    if let Some(root_li) = nested {
        list.children.push(root_li);
    }
}

fn nest_li_like_libxml(li: &mut IrNode, inner: IrNode) {
    if let Some(anchor) = primary_anchor_mut(li) {
        // libxml keeps the next <li> inside the still-open content <div>.
        if let Some(last) = anchor.children.last_mut().filter(|c| c.name == "div") {
            last.children.push(inner);
        } else {
            anchor.children.push(inner);
        }
    } else {
        li.children.push(inner);
    }
}

fn blackhole_following_siblings(node: &mut IrNode) {
    for child in &mut node.children {
        blackhole_following_siblings(child);
    }

    // Keep footer as a body-level sibling so article titles are not polluted.
    if matches!(node.name.as_str(), "body" | "html") {
        return;
    }

    let Some(i) = node.children.iter().position(subtree_has_mended_list) else {
        return;
    };
    if i + 1 >= node.children.len() {
        return;
    }

    let drained: Vec<IrNode> = node.children.drain(i + 1..).collect();
    let (landmarks, rest): (Vec<_>, Vec<_>) = drained
        .into_iter()
        .partition(|sib| matches!(sib.name.as_str(), "footer" | "header" | "nav"));

    if !rest.is_empty() {
        if let Some(anchor) = open_anchor_for_blackhole(&mut node.children[i]) {
            anchor.children.extend(rest);
        } else {
            node.children[i].children.extend(rest);
        }
    }
    node.children.extend(landmarks);
}

/// libxml closes the innermost card via `</a></li></ul>`, then keeps outer `a`s open.
/// Following siblings attach to the parent of the deepest `a` when a carousel chain exists.
fn open_anchor_for_blackhole(node: &mut IrNode) -> Option<&mut IrNode> {
    let path = path_to_innermost_anchor(node);
    let use_parent = subtree_has_mended_list(node);
    let a_path_lens = a_lengths_along_path(node, &path);

    if a_path_lens.is_empty() {
        return None;
    }

    let target_len = if use_parent && a_path_lens.len() >= 2 {
        a_path_lens[a_path_lens.len() - 2]
    } else {
        *a_path_lens.last().unwrap()
    };

    if target_len == 0 {
        return (node.name == "a").then_some(node);
    }

    let mut cur = node;
    for &idx in &path[..target_len] {
        cur = &mut cur.children[idx];
    }
    (cur.name == "a").then_some(cur)
}

fn a_lengths_along_path(node: &IrNode, path: &[usize]) -> Vec<usize> {
    let mut out = Vec::new();
    if node.name == "a" {
        out.push(0);
    }
    let mut cur = node;
    for (len, &idx) in path.iter().enumerate() {
        cur = &cur.children[idx];
        if cur.name == "a" {
            out.push(len + 1);
        }
    }
    out
}

fn path_to_innermost_anchor(node: &IrNode) -> Vec<usize> {
    let mut path = Vec::new();
    let mut cur = node;
    while let Some(i) = cur.children.iter().position(contains_any_anchor) {
        path.push(i);
        cur = &cur.children[i];
        if cur.name == "a" && !cur.children.iter().any(contains_any_anchor) {
            break;
        }
    }
    path
}

fn subtree_has_mended_list(node: &IrNode) -> bool {
    is_mended_list(node) || node.children.iter().any(subtree_has_mended_list)
}

fn is_mended_list(node: &IrNode) -> bool {
    if !matches!(node.name.as_str(), "ul" | "ol") || node.children.len() != 1 {
        return false;
    }
    let li = &node.children[0];
    if li.name != "li" {
        return false;
    }
    let Some(anchor) = li.children.iter().find(|c| c.name == "a") else {
        return false;
    };
    anchor.children.iter().any(contains_li)
}

fn contains_li(node: &IrNode) -> bool {
    node.name == "li" || node.children.iter().any(contains_li)
}

fn is_split_anchor_li(li: &IrNode) -> bool {
    let Some(first) = li.children.first() else {
        return false;
    };
    if first.name != "a" || first.attrs.href.is_none() || !first.children.is_empty() {
        return false;
    }
    let href = first.attrs.href.as_deref().unwrap();
    li.children
        .iter()
        .skip(1)
        .any(|sib| contains_anchor_with_href(sib, href))
}

fn merge_split_anchor_li(li: &mut IrNode) {
    if !is_split_anchor_li(li) {
        return;
    }
    let href = li.children[0].attrs.href.clone().expect("checked");
    let find_idx = li
        .children
        .iter()
        .enumerate()
        .skip(1)
        .find_map(|(i, sib)| contains_anchor_with_href(sib, &href).then_some(i));
    let Some(sib_idx) = find_idx else {
        return;
    };

    let mut sib = li.children.remove(sib_idx);
    unwrap_anchor_with_href(&mut sib, &href);
    li.children[0].children.push(sib);
}

fn primary_anchor_mut(li: &mut IrNode) -> Option<&mut IrNode> {
    li.children.iter_mut().find(|c| c.name == "a")
}

fn contains_any_anchor(node: &IrNode) -> bool {
    node.name == "a" || node.children.iter().any(contains_any_anchor)
}

fn contains_anchor_with_href(node: &IrNode, href: &str) -> bool {
    if node.name == "a" && node.attrs.href.as_deref() == Some(href) {
        return true;
    }
    node.children
        .iter()
        .any(|child| contains_anchor_with_href(child, href))
}

fn unwrap_anchor_with_href(node: &mut IrNode, href: &str) {
    if node.name == "a" && node.attrs.href.as_deref() == Some(href) {
        return;
    }
    let mut i = 0;
    while i < node.children.len() {
        if node.children[i].name == "a" && node.children[i].attrs.href.as_deref() == Some(href) {
            let a = node.children.remove(i);
            for (offset, child) in a.children.into_iter().enumerate() {
                node.children.insert(i + offset, child);
            }
            return;
        }
        unwrap_anchor_with_href(&mut node.children[i], href);
        i += 1;
    }
}

fn reindex(node: &mut IrNode, path: &str, depth: usize, chrome: bool) {
    node.depth = depth;
    node.tag_path = if path.is_empty() {
        format!("/{}", node.name)
    } else {
        format!("{path}/{}", node.name)
    };
    node.chrome = chrome || ignored_container(&node.name);
    let chrome_here = node.chrome;
    let child_path = node.tag_path.clone();
    for child in &mut node.children {
        reindex(child, &child_path, depth + 1, chrome_here);
    }
}

/// Count element nodes after structural mends (duplicate anchors may be removed).
pub fn count_nodes(node: &IrNode) -> usize {
    1 + node.children.iter().map(count_nodes).sum::<usize>()
}
