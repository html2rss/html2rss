# FeedPipeline — `auto` request strategy

`:auto` is the default request plan for feed builds (`auto_source`, `auto_json_feed`, Capture, and MCP `scrape` / `capture`). `FeedPipeline::StrategyPlan` resolves it; `FeedPipeline::AutoFallback` executes `AutoFallback::CHAIN`.

Use `:auto` when you want Faraday first and a browser-backed hop only if that fetch fails or yields zero items. Pin a concrete strategy (`faraday`, `botasaurus`, `local_file`) when you need a single transport.

## Chain

`AutoFallback::CHAIN` is:

1. **Faraday** — plain HTTP (faster, cheaper).
2. **Botasaurus** — attempted when Faraday raises a fallback-eligible error (for example `BlockedSurfaceDetected` or timeout) or extracts zero feed items.

Before escalating Faraday → Botasaurus on a **weak** auto-source extract (empty / below floor / high-entropy / app-shell / unsupported — not blocked), `FeedResolution` may probe up to five same-origin listing or native-feed candidates and rewrite the effective scrape URL via {ScrapeTarget}. Botasaurus then uses the resolved URL. Direct RSS/Atom entry URLs are parsed via `Syndication::Parser` without HTML AutoSource.

There is no Browserless / Puppeteer-in-gem tier. Pin `botasaurus` when you want browser rendering without Faraday first. Botasaurus needs `BOTASAURUS_SCRAPER_URL`.

## Surfaces

| Surface                                  | `:auto` behavior                                                                                                                   |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Gem / CLI `apply`, MCP `scrape`, Capture | Full AutoFallback chain (`faraday` → `botasaurus`)                                                                                 |
| MCP `inspect`                            | Cheap diagnostic: `StrategyPlan.concrete_for_diagnostic` maps `auto` to Faraday (pin `botasaurus` when you need browser rendering) |

## Fallback vs abort

These typically hop to the next chain member (among other `StandardError`s `AutoFallback` rescues):

- `Html2rss::RequestService::BlockedSurfaceDetected`
- `Html2rss::RequestService::RequestTimedOut`
- Faraday connection / timeout errors
- Empty extraction results when a later chain member may succeed

These abort immediately (`AutoFallback::NON_FALLBACK_ERRORS`): unknown strategy, invalid URL, unsupported scheme, budget exceeded, private network denied, cross-origin follow-up denied, response too large.

Retries share the feed's request/session policy. Pin a concrete strategy when you need a single-hop budget profile.

## Success signals

- `Html2rss::RequestService::Response` includes transport metadata for the strategy that produced it.
- `Html2rss::Status` records selected strategy and attempt tallies for MCP envelope payload / CLI `--explain`.
- Fallback hops log at info/warn (`AutoFallback`).

See also {Html2rss::AutoSource} for article scraping (a different pipeline) and {Html2rss::Capture} for durable configs that stamp the selected strategy.
