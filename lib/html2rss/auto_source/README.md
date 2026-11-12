# AutoSource

How html2rss builds feed items when a config has no (or incomplete) CSS selectors.

## What and when

`Html2rss.auto_source` / `auto_json_feed` (and any feed config with `auto_source:`) fetch a page once, then run an ordered set of scrapers against that response. Use it when you want “guess articles from this URL” without hand-writing selectors. Prefer explicit `selectors:` when you already know the list markup — that path stays on Nokogiri + `Html::Navigator`.

Entry: `FeedPipeline` → `AutoSource#articles` → `Scraper.build_instance` → per-scraper extraction → `Cleanup`.

## Live flow

1. **Request** — `RequestSession` returns a `Response` with `body` (String) and `parsed_body` (Nokogiri HTML, or parsed JSON for JSON media types). Direct syndication responses skip HTML scrapers and parse via `Syndication::Parser`.
2. **JSON document body** — When the response is a JSON media type (`Response#json_response?`), AutoSource runs `JsonDocument` only (no HTML tiers). Scalar JSON is `unsupported_surface`. Same-domain Cleanup stays on by default (`keep_different_domain: false`). If the scraper yielded items and Cleanup kept none, `Log.warn` emits `auto_source.admission_emptied` with drop tallies; a `different_domain` tally hints at `auto_source.cleanup.keep_different_domain: true` / `--keep-different-domain`, which lets the remote source control off-domain link targets (no affiliation or safety check); a `sponsored` tally hints at `auto_source.cleanup.keep_sponsored: true` / `--keep-sponsored`. Guidance stays in help/docs and that structured warning — stdout feed output stays composable.
3. **Scraper tiers** (HTML only) — Enabled scrapers that claim the page (shallow `articles?` or instance `extractable?`) run in `Scraper::SCRAPER_TIERS` order. Merge within a tier, then stop when enough articles survive Cleanup:

   0. Native feed: NativeFeed (head alternates + path discovery → RSS/Atom/RDF parse)
   1. In-page structured: Schema, Microdata, Microformats2, JsonState, XhrArticles
   2. Follow-up IO: WordPress API, Sitemap, MetaOembed
   3. Heuristic: SemanticHtml
   4. Heuristic: Html (skipped when earlier tiers already admitted at least one clean article)

4. **Structured / API scrapers** — Schema, Microdata, MF2, JSON state, XHR JSON, oEmbed, WordPress REST, and Sitemap work on Nokogiri CSS/XPath or JSON/XML parsers. They do not extract from SST. `JsonDocument` walks a JSON response body (JSON Feed mapping or `JsonState.discover_articles`).
5. **Heuristic scrapers** — `SemanticHtml` and `Html` share the page `SST::Document` (built lazily, at most once per page, by the first consumer: a heuristic tier or the page check), then:

   `SST::Normalizer` → `AutoSource::Segmenter` → `Scoring::Engine` → extractor / article materialization.

6. **Cleanup** — Page-check structured items, merge, dedupe, drop explicitly sponsored items, hard-exclude non-article destinations (via `PathClassifier` facts), drop untitled page-derived items (`blank_title`; publisher feeds may carry untitled posts) and junk titles, and trim to `limit`. Titles from the heuristic scrapers (`Scraper::HEURISTIC_SCRAPERS`) reach Cleanup composed by `Article::Title` (`Kicker: Headline`, no teaser clock, label or type noise); every other scraper carries a publisher-declared headline (structured data, feeds, APIs) and keeps it verbatim apart from whitespace collapse and invisible characters (soft hyphens, zero-width characters). Cleanup rejects junk titles but never rewrites them. Html is skipped when earlier tiers already admitted clean items.

   Page check: items from `Scraper::CORROBORATED_SCRAPERS` go through `Corroboration#verdict` before dedupe. `PageLinks` places each URL on the rendered page (content, peripheral, chrome, absent). Content keeps; chrome-only drops as `chrome_only`; unrendered drops as `not_on_page` when the page renders at least half of the item's scraper cohort (or the cohort has fewer than three items), otherwise it is scored with absence counting against it; peripheral items, and any item on a sparse page or a JSON response (no page), keep only on a private article-likeness score, else `unlikely`. Dropped items never count toward tier stop, so the heuristic tiers run and merge; `PageLinks` keys URLs by `Url#article_identity` (ignores scheme, fragment, trailing slash, and tracking query params; other params stay significant), the same key Cleanup dedupes by. A kept structured item whose URL differs from its rendered content anchor only by those takes the anchor's URL minus tracking params, never downgraded from `https` to `http`, so the item guid stays stable (`PageLinks#canonical_url` via `Corroboration#canonical_url`), so it merges with the heuristic copy; for a shared URL the kept structured copy wins dedupe.

   Sponsored items: `PageLinks` marks a URL sponsored when every card linking it carries a `LinkDestination::Sponsorship` marker. A container marker (`rel="sponsored"`, a truthy `data-sponsored`/`data-advertorial`, a sponsored class token such as `card--sponsored`, or an ARIA ad label) marks every destination inside it; a label (an ad-label class, or a standalone element whose whole text is a paid label such as "Anzeige" or "Sponsored by …") marks the headline destination of the `article`, `section`, `aside` or `li` it sits in, and nothing outside such a card. Label words in headlines, anchors, topic chips or prose, and unpaid attribution ("Presented by …"), never count. Cleanup drops such items from page-derived scrapers as `sponsored`; `auto_source.cleanup.keep_sponsored: true` keeps them.

7. **Entry URL resolution** (pipeline, not this class) — when AutoFallback sees a weak homepage extract, `FeedResolution` may rewrite the scrape URL to a listing/feed before escalating strategies. See {Html2rss::FeedPipeline} and {Html2rss::FeedResolution}.

Segmenter strategies: `:semantic` (leaf containers + primary link), `:list` (cards grouped by parent; `main` is a filter), `:cluster` (class/structure grids for anchorless cards). Scoring ranks and demotes; `LinkDestination::NoisePolicy` owns content-anchor eligibility. Cleanup owns feed-item admission.

## Nokogiri vs SST boundaries

| Surface                                                                                       | Owns DOM                                                         |
| --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `Response#parsed_body`                                                                        | HTML document, or Hash/Array for JSON bodies                     |
| `JsonDocument`                                                                                | Parsed JSON Hash/Array (no Nokogiri)                             |
| Schema / Microdata / MF2 / JsonState / XhrArticles / MetaOembed / app-shell detection         | Nokogiri (items page-checked against SST anchors via `PageLinks`) |
| Sitemap detection (CSS/XPath)                                                                 | Nokogiri; URL list parsing uses raw `response.body` (XML string) |
| Selectors path / Sanitize transformers                                                        | Nokogiri (unchanged)                                             |
| `SST::Normalizer`                                                                             | Sole Nokogiri consumer on the heuristic auto-source path         |
| Segmenter, Scoring, `Html::SstArticleExtractor`, heuristic chrome (`SST::Tags` / `SST::Text`) | SST only                                                         |

Production heuristic scrapers and the page check reuse one `SST::Document` and one page `Scoring::LinkResolver` memoized by `AutoSource`, not re-parse HTML strings.

## Constraints

- **`SST::Normalizer::MAX_NODES` (5_000)** — Beyond this, normalization degrades to a semantic-tag-only keep set and logs a warning.
- **Top-K** — `Scoring::Engine::TOP_K` (99) caps ranked segments materialized into articles; list strategy also budgets `use_top_selectors`.
- **Typed stages** — Pipeline stages take `SST::Document` / `Segment` / `RankedSegment`, not ad-hoc Hash bags. Internal scraper APIs may change; the public gem surface is `lib/html2rss.rb`.

## Measuring changes

Precision and recall changes are measured on the labeled corpus (`bin/auto-source-corpus`, ratchet spec, `make corpus-baseline`); see `CONTEXT.md` § Auto-source corpus. Wall/alloc budgets: `make perf-baseline`. Revision-to-revision effect on saved real pages: `bin/compare-revisions`.

## Non-goals

- Replacing Selectors, Schema, Microdata, MF2, JsonState, JsonDocument, or XhrArticles with SST.
- Turning `keep_different_domain` on automatically for JSON documents (operators must opt in explicitly; the flag trusts the source for any published link domain).
- A second HTML parser beside Nokogiri.
- Dual Response payload (Nokogiri + SST always).
- App-shell classification on SST.
- Rewriting Sanitize transformers off Nokogiri.

See also {file:CONTEXT CONTEXT.md} for module ownership (chrome, scoring, clustering), {Html2rss::FeedPipeline} for the request-strategy fallback chain (unrelated to article scraping), and {Html2rss::Capture} to turn a listing URL into a durable items-selector config.
