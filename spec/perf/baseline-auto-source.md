# Auto-source performance baseline

Captured: 2026-09-02T19:48:22Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)
Backends: nokogiri, nokolexbor, rust

## Comparison (vs nokogiri)

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.204234 | 724283 | — | — |
| nokolexbor | 0.178894 | 687535 | -12.4 | -5.1 |
| rust | 0.183354 | 727240 | -10.2 | +0.4 |

## Backend: nokogiri

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.204234 |
| allocations (median) | 724283 |
| wall_budget_1_1x | 0.224657 |
| alloc_budget_1_15x | 832926 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: nokolexbor

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.178894 |
| allocations (median) | 687535 |
| wall_budget_1_1x | 0.196783 |
| alloc_budget_1_15x | 790666 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: rust

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.183354 |
| allocations (median) | 727240 |
| wall_budget_1_1x | 0.201689 |
| alloc_budget_1_15x | 836326 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
