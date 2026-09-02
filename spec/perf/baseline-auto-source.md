# Auto-source performance baseline

Captured: 2026-09-02T20:13:02Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)
Backends: nokogiri, nokolexbor, rust

## Comparison (vs nokogiri)

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.190699 | 724247 | — | — |
| nokolexbor | 0.166111 | 687590 | -12.9 | -5.1 |
| rust | 0.175511 | 633531 | -8.0 | -12.5 |

## Backend: nokogiri

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.190699 |
| allocations (median) | 724247 |
| wall_budget_1_1x | 0.209769 |
| alloc_budget_1_15x | 832885 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: nokolexbor

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.166111 |
| allocations (median) | 687590 |
| wall_budget_1_1x | 0.182722 |
| alloc_budget_1_15x | 790729 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: rust

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.175511 |
| allocations (median) | 633531 |
| wall_budget_1_1x | 0.193062 |
| alloc_budget_1_15x | 728561 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
