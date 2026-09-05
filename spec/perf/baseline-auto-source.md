# Auto-source performance baseline

Captured: 2026-09-02T20:28:07Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)
Backends: nokogiri, nokolexbor, rust

## Comparison (vs nokogiri)

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.185460 | 724257 | — | — |
| nokolexbor | 0.160261 | 687616 | -13.6 | -5.1 |
| rust | 0.166509 | 699283 | -10.2 | -3.4 |

## Backend: nokogiri

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.185460 |
| allocations (median) | 724257 |
| wall_budget_1_1x | 0.204006 |
| alloc_budget_1_15x | 832896 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: nokolexbor

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.160261 |
| allocations (median) | 687616 |
| wall_budget_1_1x | 0.176287 |
| alloc_budget_1_15x | 790759 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: rust

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.166509 |
| allocations (median) | 699283 |
| wall_budget_1_1x | 0.183160 |
| alloc_budget_1_15x | 804176 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
