# Heuristic auto-source performance baseline

Captured: 2026-08-13T10:50:56Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html
Warmup runs: 1; measured runs: 5 (median reported)

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.841104 |
| allocations (median) | 843466 |
| wall_budget_1_1x | 0.925214 |
| alloc_budget_1_15x | 969986 |

Article counts per fixture (semantic, html):
- spec/fixtures/page_1.html: semantic=105, html=80
- spec/fixtures/multi_link_block.html: semantic=5, html=5
- spec/fixtures/local_feed_test.html: semantic=2, html=2
