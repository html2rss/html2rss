# Capture — Automatic Feed Config Derivation

The `Html2rss.capture` method (and its CLI alias `html2rss capture`) analyzes
any URL through the auto-source pipeline and produces a reusable feed config
hash with derived CSS selectors.

## Use Case

Speed up writing feed configs. Instead of manually inspecting HTML to craft CSS
selectors, point `capture` at your target URL and let it produce a first draft.
Tweak the output as needed.

## Gem API

```ruby
config = Html2rss.capture('https://example.com/articles')

# config contains a hash with :channel and :selectors keys:
# {
#   channel: { url: "https://example.com/articles", title: "...", time_zone: "UTC" },
#   selectors: {
#     items: { selector: "div.post" },
#     title: { selector: "h2 > a" },
#     link: { selector: "a.more", extractor: "href" },
#     description: { selector: "div.excerpt" }
#   }
# }

# Save to YAML for reuse (string keys — same wire form as hand-written configs)
File.write('my-feed.yml', YAML.dump(Html2rss::HashUtil.deep_stringify_keys(config)))

# Use immediately
feed = Html2rss.feed(config)
```

### Options

```ruby
# Pin a specific request strategy
Html2rss.capture('https://spa-site.com', strategy: :botasaurus)

# Provide a CSS selector hint for items
Html2rss.capture('https://example.com', items_selector: '.article-card')

# Analyze a local HTML file (stamps strategy: :local_file and local_file_path)
Html2rss.capture('https://example.com', strategy: :local_file, local_file_path: './page.html')
```

## CLI

```bash
# Print a reusable YAML config
html2rss capture https://example.com/articles

# With Botasaurus strategy
html2rss capture https://example.com --strategy botasaurus

# Save to file
html2rss capture https://example.com/articles > my-feed.yml

# Read from a local HTML file
html2rss capture https://example.com --input ./page.html
```

## How It Works

1. **Request** — fetches the page using the configured strategy
2. **Discover** — runs the AutoSource pipeline to extract articles
3. **Analyze** — normalizes the page into an SST document, segments it, and
   maps segment positions back to extracted articles
4. **Derive** — builds CSS selectors from SST tag_paths for items, title, link,
   and description attributes
5. **Assemble** — returns a complete config hash ready for serialization

## Limitations

- Selector quality depends on the page structure and auto-source detection.
  Complex layouts may produce imperfect selectors that need manual adjustment.
  Treat capture output as a first draft.
- Capture segment discovery currently uses the list Segmenter strategy only
  (not AutoSource's cluster/semantic heuristics), so some layouts may need a
  manual `items_selector` hint.
- The capture only derives items, title, link, and description selectors.
  Description is omitted when it would resolve to the invalid CSS selector `.`
  (item root equals description root). Additional attributes (author,
  published_at, categories, enclosures) can be added manually.
