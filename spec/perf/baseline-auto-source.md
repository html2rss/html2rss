# Auto-source performance baseline

Captured: 2026-11-11T17:38:28Z
Ruby: 4.0.0
Fixtures: spec/fixtures/page_1.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html, spec/fixtures/auto_source/corpus/menu_mixed_top_level.html, spec/fixtures/auto_source/corpus/schema_footer_extras.html, spec/fixtures/auto_source/corpus/structured_small_merge.html
Warmup runs: 1; measured runs: 5 (median reported)

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.137432 |
| allocations (median) | 598805 |
| wall_budget_1_1x | 0.151175 |
| alloc_budget_1_15x | 688626 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/page_1.html: semantic=65, html=21, auto_source=13
- spec/fixtures/multi_link_block.html: semantic=3, html=5, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
- spec/fixtures/auto_source/corpus/menu_mixed_top_level.html: semantic=5, html=5, auto_source=5
- spec/fixtures/auto_source/corpus/schema_footer_extras.html: semantic=4, html=4, auto_source=4
- spec/fixtures/auto_source/corpus/structured_small_merge.html: semantic=6, html=6, auto_source=6
