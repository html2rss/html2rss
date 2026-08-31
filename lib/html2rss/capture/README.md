# Capture

`Html2rss.capture` (and CLI `html2rss capture`) analyzes a URL through the feed pipeline and produces a reusable config with **items selector + `enhance: true` only** — no title/url/description attribute-selector soup. At feed-build time, `enhance: true` fills missing article fields via `Html::ArticleExtractor` on each matched item.

## Breaking change

`Html2rss.capture` / `Capture.build` return `Capture::CaptureResult`, not a bare Hash.

| Before | After |
| --- | --- |
| `config = Html2rss.capture(url)` then `Config.to_yaml(config)` | `result = Html2rss.capture(url)` then `result.yaml` or `Config.to_yaml(result.config)` |

No compatibility shim: callers must use `#config` / `#yaml`.

## When to use it

Point `capture` at a listing URL when you want a first-draft YAML config instead of hand-writing selectors. Treat the output as a draft: selector quality depends on page structure.

## Gem API

```ruby
result = Html2rss.capture('https://example.com/articles')

# result.config =>
# {
#   channel: { url: "...", title: "...", time_zone: "UTC" },
#   selectors: {
#     items: { selector: "div.post", enhance: true }
#   }
# }

File.write('my-feed.yml', result.yaml)
feed = Html2rss.feed(result.config)
```

`Html2rss.capture` and `Capture.build` both return a `CaptureResult` with YAML (`#yaml`, includes the schema modeline) and quality meta (`has_selectors`, `segment_strategy`, `admission_drops`, `selected_strategy`, `native_feed`).

### Options

```ruby
Html2rss.capture('https://spa-site.com', strategy: :botasaurus)
Html2rss.capture('https://example.com', items_selector: '.article-card')
Html2rss.capture('https://example.com', strategy: :local_file, local_file_path: './page.html')
Html2rss.capture('https://example.com', max_redirects: 8, max_requests: 4)
```

`strategy: :auto` uses the same AutoFallback chain as scrape (`faraday` → `botasaurus`). When AutoFallback selects a concrete strategy (or you pin one), Capture **stamps** `strategy:` into the emitted config so later `Html2rss.feed(config)` replays the same transport.

## CLI

```bash
html2rss capture https://example.com/articles
html2rss capture https://example.com --strategy botasaurus
html2rss capture https://example.com --max-redirects 8 --max-requests 4
html2rss capture https://example.com/articles > my-feed.yml
html2rss capture https://example.com --input ./page.html
html2rss capture https://example.com --explain   # quality JSON on stderr; YAML on stdout
```

## How it works

1. **Request** — `FeedPipeline` (AutoFallback when `:auto`)
2. **Discover** — AutoSource extracts admitted articles
3. **Segment** — try SST Segmenter strategies `:list` → `:cluster` → `:semantic`
4. **Gate** — emit items selector only when ≥ `MIN_SELECTOR_MATCHES` (2) articles match
5. **Assemble** — `{ items: { selector:, enhance: true } }` plus channel

## Constraints

- Selector quality depends on page structure; treat output as a first draft.
- When the quality gate fails, selectors are omitted (`has_selectors: false`) rather than inventing attribute selectors.
- Botasaurus hops need `BOTASAURUS_SCRAPER_URL`.

See also {Html2rss::AutoSource} for article discovery and {Html2rss::FeedPipeline} for the `:auto` request chain.
