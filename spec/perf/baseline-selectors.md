# Selectors performance baseline

Captured: 2026-10-04T12:32:21Z
Ruby: 4.0.7
Cases: performance_optimized_site, combined_scraper_sources, conditional_processing_site, page_1
Warmup runs: 1; measured runs: 5 (median reported)

| Metric | Value |
| --- | --- |
| wall_time_s (median) | 0.023201 |
| allocations (median) | 46164 |
| wall_budget_1_1x | 0.025521 |
| alloc_budget_1_15x | 53089 |

Article counts per case:
- performance_optimized_site: 4
- combined_scraper_sources: 6
- conditional_processing_site: 6
- page_1: 14
