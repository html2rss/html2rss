# Feed building performance baseline

Captured: 2026-11-13T10:35:42Z
Ruby: 4.0.0
Cases: news_feed_render, podcast_feed_render, native_feed_parse
Warmup runs: 1; measured runs: 5

| Metric | Value |
| --- | --- |
| wall_time_s (min of 5) | 0.011866 |
| allocations (median of 5) | 46198 |
| wall_budget_s (1.1x min, advisory) | 0.013053 |
| alloc_budget (1.15x median, hard gate) | 53128 |

Item counts per case:
- news_feed_render: rss_items=25, json_items=25
- podcast_feed_render: rss_items=5, json_items=5
- native_feed_parse: items=5
