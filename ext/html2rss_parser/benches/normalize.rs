//! Microbenches for SST normalize paths.
//!
//! Run from repo root:
//!   mise exec -- cargo bench --manifest-path ext/html2rss_parser/Cargo.toml \
//!     --bench normalize --no-default-features

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use html2rss_parser::sst::normalize;
use scraper::Html;
use std::fs;
use std::path::PathBuf;

const SMALL_HTML: &str = r#"<html><body>
  <script>evil()</script>
  <nav><a href="/home">Home</a></nav>
  <main>
    <article class="card teaser" data-id="1"><a href="/p">Post</a><p>Hello</p></article>
    <article class="card"><a href="/q">Other</a></article>
  </main>
</body></html>"#;

fn fixture_page_1() -> Option<String> {
    let candidates = [
        PathBuf::from("spec/fixtures/page_1.html"),
        PathBuf::from("../../spec/fixtures/page_1.html"),
        PathBuf::from("../../../spec/fixtures/page_1.html"),
    ];
    candidates.into_iter().find_map(|p| fs::read_to_string(p).ok())
}

fn bench_normalize_string(c: &mut Criterion) {
    let mut group = c.benchmark_group("sst_normalize");

    group.bench_function("string_small", |b| {
        b.iter(|| normalize::normalize(black_box(SMALL_HTML)).expect("normalize"))
    });

    if let Some(page) = fixture_page_1() {
        group.bench_function("string_page_1", |b| {
            b.iter(|| normalize::normalize(black_box(&page)).expect("normalize"))
        });

        // Legacy double-work Document#to_sst (serialize + reparse) for comparison.
        group.bench_function("parse_then_string_normalize_page_1", |b| {
            b.iter(|| {
                let html = Html::parse_document(black_box(&page));
                let serialized = html.html();
                normalize::normalize(black_box(&serialized)).expect("normalize")
            })
        });

        // Phase 1 win: one parse, then walk the existing tree.
        group.bench_function("parse_then_from_html_page_1", |b| {
            b.iter(|| {
                let html = Html::parse_document(black_box(&page));
                normalize::normalize_from_html(black_box(&html)).expect("normalize")
            })
        });

        let parsed = Html::parse_document(&page);
        group.bench_function("from_html_only_page_1", |b| {
            b.iter(|| normalize::normalize_from_html(black_box(&parsed)).expect("normalize"))
        });
    }

    group.finish();
}

criterion_group!(benches, bench_normalize_string);
criterion_main!(benches);
