# Auto-source performance baseline

Captured: 2026-09-16T20:43:55Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.224917 |
| allocations (median) | 711500 |
| wall_budget_1_1x | 0.247409 |
| alloc_budget_1_15x | 818225 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=61, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=3, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
