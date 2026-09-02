//! Pure HTML parse (scraper / html5ever). No Magnus imports.

use scraper::Html;

/// Parse an HTML document string.
pub fn parse_document(html: &str) -> Html {
    Html::parse_document(html)
}
