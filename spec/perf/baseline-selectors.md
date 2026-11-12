# Selectors performance baseline

Captured: 2026-11-12T12:53:21Z
Ruby: 4.0.0
Cases: performance_optimized_site, combined_scraper_sources, conditional_processing_site, page_1
Warmup runs: 1; measured runs: 5

| Metric | Value |
| --- | --- |
| wall_time_s (min of 5) | 0.019346 |
| allocations (median of 5) | 52557 |
| wall_budget_s (1.1x min, advisory) | 0.021281 |
| alloc_budget (1.15x median, hard gate) | 60441 |

Article counts per case:
- performance_optimized_site: 4
- combined_scraper_sources: 6
- conditional_processing_site: 6
- page_1: 14
