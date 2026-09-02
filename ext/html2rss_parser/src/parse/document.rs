//! Parse HTML into a scraper document (Phase 2+).

use scraper::Html;

/// Parse an HTML document string.
///
/// # Errors
///
/// `scraper::Html::parse_document` does not fail on typical markup; this wrapper
/// exists so call sites use `Result` consistently once validation is added.
#[allow(dead_code)] // wired in Phase 2
pub fn parse_document(html: &str) -> Result<Html, String> {
    Ok(Html::parse_document(html))
}
