# Capture — Durable Feed Config Derivation

The `Html2rss.capture` method (and CLI `html2rss capture`) analyzes a URL through
the feed pipeline and produces a reusable config with **items selector + `enhance: true`**
only — no brittle title/url/description attribute soup.

This implements the durable shape described in issue #212.

## Use Case

Speed up writing feed configs. Point `capture` at a listing URL and get a first draft
that fills article fields via enhance at feed-build time.

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

`Capture.build` returns a `CaptureResult` with quality meta (`has_selectors`,
`segment_strategy`, `admission_drops`, `selected_strategy`).

### Options

```ruby
Html2rss.capture('https://spa-site.com', strategy: :botasaurus)
Html2rss.capture('https://example.com', items_selector: '.article-card')
Html2rss.capture('https://example.com', strategy: :local_file, local_file_path: './page.html')
```

`strategy: :auto` uses the same AutoFallback chain as scrape (`faraday` → `botasaurus`).

## CLI

```bash
html2rss capture https://example.com/articles
html2rss capture https://example.com --strategy botasaurus
html2rss capture https://example.com/articles > my-feed.yml
html2rss capture https://example.com --input ./page.html
html2rss capture https://example.com --explain   # quality JSON on stderr
```

## How It Works

1. **Request** — `FeedPipeline` (AutoFallback when `:auto`)
2. **Discover** — AutoSource extracts admitted articles
3. **Segment** — try SST Segmenter strategies `:list` → `:cluster` → `:semantic`
4. **Gate** — emit items selector only when ≥ `MIN_SELECTOR_MATCHES` articles match
5. **Assemble** — `{ items: { selector:, enhance: true } }` plus channel

## Limitations

- Selector quality depends on page structure; treat output as a first draft.
- When the quality gate fails, selectors are omitted (`has_selectors: false`) — fail loud
  rather than inventing attribute selectors.
