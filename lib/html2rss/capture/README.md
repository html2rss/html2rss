# Capture

`Html2rss.capture` (and CLI `html2rss capture`) analyzes a URL through the feed pipeline and produces a reusable config with **items selector + `enhance: true` only** — no title/url/description attribute-selector soup. At feed-build time, `enhance: true` fills missing article fields via `Html::ArticleExtractor` on each matched item.

## When to use it

Point `capture` at a listing URL when you want a first-draft YAML config instead of hand-writing selectors. Treat the output as a draft: selector quality depends on page structure.

## Gem API

```ruby
config = Html2rss.capture('https://example.com/articles')

# {
#   channel: { url: "...", title: "...", time_zone: "UTC" },
#   selectors: {
#     items: { selector: "div.post", enhance: true }
#   }
# }

File.write('my-feed.yml', YAML.dump(Html2rss::HashUtil.deep_stringify_keys(config)))
feed = Html2rss.feed(config)
```

`Capture.build` returns a `CaptureResult` with quality meta (`has_selectors`, `segment_strategy`, `admission_drops`, `selected_strategy`). `Html2rss.capture` returns only the config hash.

### Options

```ruby
Html2rss.capture('https://spa-site.com', strategy: :botasaurus)
Html2rss.capture('https://example.com', items_selector: '.article-card')
Html2rss.capture('https://example.com', strategy: :local_file, local_file_path: './page.html')
```

`strategy: :auto` uses the same AutoFallback chain as scrape (`faraday` → `botasaurus`). When AutoFallback selects a concrete strategy (or you pin one), Capture **stamps** `strategy:` into the emitted config so later `Html2rss.feed(config)` replays the same transport.

## CLI

```bash
html2rss capture https://example.com/articles
html2rss capture https://example.com --strategy botasaurus
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

See also [`../auto_source/README.md`](../auto_source/README.md) for article discovery and [`../feed_pipeline/README.md`](../feed_pipeline/README.md) for the `:auto` request chain.
