# Auto-source performance baseline

Captured: 2026-09-02T15:02:27Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)
Backends: nokogiri, nokolexbor

## Comparison (vs nokogiri)

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.212662 | 723700 | — | — |
| nokolexbor | 0.186589 | 687253 | -12.3 | -5.0 |

## Backend: nokogiri

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.212662 |
| allocations (median) | 723700 |
| wall_budget_1_1x | 0.233928 |
| alloc_budget_1_15x | 832255 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: nokolexbor

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.186589 |
| allocations (median) | 687253 |
| wall_budget_1_1x | 0.205248 |
| alloc_budget_1_15x | 790341 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
