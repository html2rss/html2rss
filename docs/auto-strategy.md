# Smart "auto" Request Strategy

This document describes the feed-level `:auto` request plan in `html2rss`.

## UX Philosophy & Intent

The primary goal of the `auto` strategy is to provide a "it just works" experience for gem users.

- **Zero-Config Resiliency**: Users should not need to understand anti-bot mechanisms or manually switch strategies. The gem attempts to overcome blocking using available resources.
- **Efficiency-First**: Prefer `Faraday` (working for many sites) as it is significantly faster and cheaper than browser-backed scraping.
- **Transparent Fallback**: When a fallback occurs, the gem provides clear feedback via logging and `Html2rss::Status`, helping users understand why a request took longer and which strategy ultimately succeeded.
- **Availability-Aware**: The strategy adapts to the runtime environment, utilizing Botasaurus only if `BOTASAURUS_SCRAPER_URL` is configured and reachable.

## Strategic Selection Logic

`:auto` is resolved by `FeedPipeline::StrategyPlan` and executed by `FeedPipeline::AutoFallback`. The ordered chain is:

1. **Faraday**: Default starting point (plain HTTP).
2. **Botasaurus**: Attempted if Faraday fails with a fallback-eligible error (e.g. `BlockedSurfaceDetected`) or yields zero feed items, and Botasaurus is configured.

There is no Browserless / Puppeteer-in-gem tier. Pin `botasaurus` explicitly when you want browser rendering without Faraday first.

## Tool Surfaces

| Surface | `:auto` behavior |
|---------|------------------|
| Gem / CLI feed build, `scrape_url`, Capture (durable configs) | Full AutoFallback chain (`faraday` → `botasaurus`) |
| MCP / CLI `inspect_url` | Cheap diagnostic: Faraday only (document pin `botasaurus` when needed) |

## Fallback-Eligible Errors

The following exceptions (among others owned by `AutoFallback`) typically trigger a hop to the next chain member:

- `Html2rss::RequestService::BlockedSurfaceDetected`
- `Html2rss::RequestService::RequestTimedOut`
- Faraday connection / timeout errors
- Empty extraction results when a later chain member may succeed

Non-fallback errors (budget exceeded, private network denied, invalid URL, etc.) abort immediately.

## Budget Management

Retries within the `auto` plan are budget-aware: strategy hops share the feed's request/session policy. Prefer pinning a concrete strategy when you need a single-hop budget profile.

## Strategy Reporting

- `Html2rss::RequestService::Response` includes transport metadata for the strategy that produced it.
- `Html2rss::Status` records selected strategy and attempt tallies for MCP `_meta` / CLI `--explain`.

## Default Behavior

`auto` is the default strategy for feed builds, including `auto_source` and `auto_json_feed` entry points.
