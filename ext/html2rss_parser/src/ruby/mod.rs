//! Magnus boundary only — register classes and convert IR ↔ Ruby.

use magnus::{error::Error, Module, Ruby};

mod document;
mod node;
mod sst;

/// Register `Html2rss::Html::NativeEngine` and nested types.
///
/// Reopens existing Zeitwerk modules when already defined (lazy require after Ruby load).
pub fn register(ruby: &Ruby) -> Result<(), Error> {
    let html2rss = ruby.define_module("Html2rss")?;
    let html = html2rss.define_module("Html")?;
    let native = html.define_module("NativeEngine")?;

    document::register(ruby, native)?;
    node::register(ruby, native)?;
    sst::register(ruby, native)?;

    Ok(())
}
