//! Microbenches for SST normalize paths (Phase 0+).
//!
//! Run from repo root:
//!   mise exec -- cargo bench --manifest-path ext/html2rss_parser/Cargo.toml --bench normalize
//!
//! After Phase 1, `normalize_from_html` lands; after Phase 2, IR nest build can be timed
//! separately from Magnus hydrate (hydrate stays in Ruby).

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

        // Phase 1 target: walk an already-parsed Html without re-serializing.
        // Until normalize_from_html exists, measure parse + string-normalize as the
        // double-work upper bound Document#to_sst pays today.
        group.bench_function("parse_then_string_normalize_page_1", |b| {
            b.iter(|| {
                let html = Html::parse_document(black_box(&page));
                let serialized = html.html();
                normalize::normalize(black_box(&serialized)).expect("normalize")
            })
        });
    }

    group.finish();
}

criterion_group!(benches, bench_normalize_string);
criterion_main!(benches);
