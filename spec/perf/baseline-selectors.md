# Selectors performance baseline

Captured: 2026-11-13T11:43:40Z
Ruby: 4.0.9
Cases: performance_optimized_site, combined_scraper_sources, conditional_processing_site, news_front_page
Warmup runs: 1; measured runs: 5

| Metric | Value |
| --- | --- |
| wall_time_s (min of 5) | 0.022556 |
| allocations (median of 5) | 59705 |
| wall_budget_s (1.1x min, advisory) | 0.024812 |
| alloc_budget (1.15x median, hard gate) | 68661 |

Article counts per case:
- performance_optimized_site: 4
- combined_scraper_sources: 6
- conditional_processing_site: 6
- news_front_page: 16
