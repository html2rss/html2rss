# Feed building performance baseline

Captured: 2026-11-26T10:00:42Z
Ruby: 4.0.0
Cases: news_feed_render, podcast_feed_render, native_feed_parse
Warmup runs: 1; measured runs: 5

| Metric | Value |
| --- | --- |
| wall_time_s (min of 5) | 0.018372 |
| allocations (median of 5) | 72843 |
| wall_budget_s (1.1x min, advisory) | 0.020209 |
| alloc_budget (1.15x median, hard gate) | 83770 |

Item counts per case:
- news_feed_render: rss_items=50, json_items=50
- podcast_feed_render: rss_items=5, json_items=5
- native_feed_parse: items=5
