# Capture

`Html2rss.capture` (and CLI `html2rss capture`) analyzes a URL through the feed pipeline and produces a reusable config with **items selector + `enhance: true` only** — no title/url/description attribute-selector soup. At feed-build time, `enhance: true` fills missing article fields via `Html::ArticleExtractor` on each **matched list-card item node**.

## API

`Html2rss.capture` / `Capture.build` return `Capture::CaptureResult` — use `#yaml` or `#config`, not a bare Hash.

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
rss = Html2rss.apply(result.config)
```

`Html2rss.capture` and `Capture.build` both return a `CaptureResult` with YAML (`#yaml`, includes the schema modeline) and quality meta (`has_selectors`, `segment_strategy`, `admission_drops`, `selected_strategy`, `native_feed`, `candidates`).

`#candidates` is ranked discovery evidence: `{ items:, title:, link:, published: }` arrays (best-first, deduplicated). Items entries are `{ selector:, enhance: }`; field entries are `{ selector: }` only. Buckets may be empty when evidence is missing. The default `a[href]` YAML fallback is not listed as discovered evidence.

**Wire vs internal:** user-facing **`Html2rss.apply`** ships RSS from a config Hash. Pipeline internals **`Html2rss.feed` / `feed_result`** stay unchanged — use `apply` in CLI/MCP/docs examples, not `feed`.

### Options

```ruby
Html2rss.capture('https://spa-site.com', strategy: :botasaurus)
Html2rss.capture('https://example.com', items_selector: '.article-card')
Html2rss.capture('https://example.com', strategy: :local_file, local_file_path: './page.html')
Html2rss.capture('https://example.com', max_redirects: 8, max_requests: 4)
```

`strategy: :auto` uses the same AutoFallback chain as scrape (`default` → `botasaurus`). When AutoFallback selects a concrete strategy (or you pin one), Capture **stamps** `strategy:` into the emitted config so later `Html2rss.apply(config)` replays the same transport.

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
4. **Gate** — keep a derived items selector when ≥ `MIN_SELECTOR_MATCHES` (2) articles match
5. **Assemble** — `{ items: { selector:, enhance: } }` plus channel. HTML derivation misses fall back to `Selectors::DEFAULT_ITEMS_SELECTOR` (`segment_strategy: :default`) instead of omitting selectors.

## Constraints

- Selector quality depends on page structure; treat output as a first draft.
- When HTML derivation misses (no articles, no SST document, fewer than `MIN_SELECTOR_MATCHES` pairs, or a rescued `ArgumentError`), Capture emits the default items selector with `segment_strategy: :default`. `enhance` still follows admission evidence (false when chrome drops are high). Non-HTML responses still omit selectors.
- Botasaurus hops need `BOTASAURUS_SCRAPER_URL`.

See also {Html2rss::AutoSource} for article discovery and {Html2rss::FeedPipeline} for the `:auto` request chain.
