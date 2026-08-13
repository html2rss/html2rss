# AutoSource

How html2rss builds feed items when a config has no (or incomplete) CSS selectors.

## What and when

`Html2rss.auto_source` / `auto_json_feed` (and any feed config with `auto_source:`) fetch a page once, then run an ordered set of scrapers against that response. Use it when you want “guess articles from this URL” without hand-writing selectors. Prefer explicit `selectors:` when you already know the list markup—that path stays on Nokogiri + `Html::Navigator`.

Entry: `FeedPipeline` → `AutoSource#articles` → `Scraper.instances_for` → per-scraper extraction → `Cleanup`.

## Live flow

1. **Request** — `RequestSession` returns a `Response` with `body` (String) and `parsed_body` (Nokogiri HTML).
2. **Scraper selection** — Enabled scrapers that claim the page (shallow `articles?` or instance `extractable?`) run in registry order: WordPress API, Sitemap, Schema, Microdata, Microformats2, JsonState, MetaOembed, SemanticHtml, Html.
3. **Structured / API scrapers** — Schema, Microdata, MF2, JSON state, oEmbed, WordPress REST, and Sitemap work on Nokogiri CSS/XPath or JSON/XML parsers. They do not use SST.
4. **Heuristic scrapers** — `SemanticHtml` and `Html` normalize once into an `SST::Document`, then:

   `SST::Normalizer` → `AutoSource::Segmenter` → `Scoring::Engine` → extractor / article materialization.

5. **Cleanup** — Merge, dedupe, and trim the combined article list.

Segmenter strategies: `:semantic` (leaf containers + primary link), `:list` (repeated tag paths), `:cluster` (class/structure grids for anchorless cards). Scoring owns eligibility, noise, and ranking weights—not Segmenter.

## Nokogiri vs SST boundaries

| Surface | Owns DOM |
| --- | --- |
| `Response#parsed_body` | Single HTML parse for the page |
| Schema / Microdata / MF2 / JsonState / MetaOembed / app-shell detection | Nokogiri |
| Sitemap detection (CSS/XPath) | Nokogiri; URL list parsing uses raw `response.body` (XML string) |
| Selectors path / Sanitize transformers | Nokogiri (unchanged) |
| `SST::Normalizer` | Sole Nokogiri consumer on the heuristic auto-source path |
| Segmenter, Scoring, `Html::SstArticleExtractor`, heuristic chrome (`SST::Tags` / `SST::Text`) | SST only |

Production heuristic scrapers should reuse one `SST::Document` memoized from `parsed_body` (or a shared Document passed in), not re-parse HTML strings.

## Constraints

- **`SST::Normalizer::MAX_NODES` (5_000)** — Beyond this, normalization degrades to a semantic-tag-only keep set and logs a warning.
- **Top-K** — `Scoring::Engine::TOP_K` (99) caps ranked segments materialized into articles; list strategy also budgets `use_top_selectors`.
- **Typed stages** — Pipeline stages take `SST::Document` / `Segment` / `RankedSegment`, not ad-hoc Hash bags. Internal scraper APIs may change; the public gem surface is `lib/html2rss.rb`.

## Non-goals

- Replacing Selectors, Schema, Microdata, MF2, or JsonState with SST.
- A second HTML parser beside Nokogiri.
- Dual Response payload (Nokogiri + SST always).
- App-shell classification on SST.
- Rewriting Sanitize transformers off Nokogiri.

See also `CONTEXT.md` for module ownership (chrome, scoring, clustering) and `docs/auto-strategy.md` for the request-strategy fallback chain (unrelated to article scraping).
