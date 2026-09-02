# Auto-source performance baseline

Captured: 2026-09-02T16:07:20Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)
Backends: nokogiri, nokolexbor, rust

## Comparison (vs nokogiri)

| Backend | wall_time_s | allocations | wall Δ% | alloc Δ% |
| --- | --- | --- | --- | --- |
| nokogiri | 0.188531 | 724272 | — | — |
| nokolexbor | 0.162424 | 687591 | -13.8 | -5.1 |
| rust | 0.187904 | 702936 | -0.3 | -2.9 |

## Backend: nokogiri

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.188531 |
| allocations (median) | 724272 |
| wall_budget_1_1x | 0.207384 |
| alloc_budget_1_15x | 832913 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: nokolexbor

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.162424 |
| allocations (median) | 687591 |
| wall_budget_1_1x | 0.178666 |
| alloc_budget_1_15x | 790730 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3

## Backend: rust

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.187904 |
| allocations (median) | 702936 |
| wall_budget_1_1x | 0.206694 |
| alloc_budget_1_15x | 808377 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=69, html=71, auto_source=17
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
