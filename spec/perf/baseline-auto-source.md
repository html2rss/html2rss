# Auto-source performance baseline

Captured: 2026-11-13T11:43:39Z
Ruby: 4.0.9
Fixtures: spec/fixtures/news_front_page.html, spec/fixtures/multi_link_block.html, spec/fixtures/local_feed_test.html, spec/fixtures/auto_source/corpus/menu_mixed_top_level.html, spec/fixtures/auto_source/corpus/schema_footer_extras.html, spec/fixtures/auto_source/corpus/structured_small_merge.html
Warmup runs: 1; measured runs: 5

| Metric | Value |
| --- | --- |
| wall_time_s (min of 5) | 0.157818 |
| allocations (median of 5) | 542934 |
| wall_budget_s (1.1x min, advisory) | 0.173600 |
| alloc_budget (1.15x median, hard gate) | 624375 |

Article counts per fixture (semantic, html | AutoSource#articles):
- spec/fixtures/news_front_page.html: semantic=67, html=45, auto_source=25
- spec/fixtures/multi_link_block.html: semantic=3, html=5, auto_source=3
- spec/fixtures/local_feed_test.html: semantic=3, html=3, auto_source=3
- spec/fixtures/auto_source/corpus/menu_mixed_top_level.html: semantic=5, html=5, auto_source=5
- spec/fixtures/auto_source/corpus/schema_footer_extras.html: semantic=4, html=4, auto_source=4
- spec/fixtures/auto_source/corpus/structured_small_merge.html: semantic=6, html=6, auto_source=6
