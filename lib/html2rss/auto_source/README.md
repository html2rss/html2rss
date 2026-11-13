# AutoSource

How html2rss builds feed items when a config has no (or incomplete) CSS selectors.

## What and when

`Html2rss.auto_source` / `auto_json_feed` (and any feed config with `auto_source:`) fetch a page once, then run an ordered set of scrapers against that response. Use it when you want “guess articles from this URL” without hand-writing selectors. Prefer explicit `selectors:` when you already know the list markup — that path stays on Nokogiri + `Html::Navigator`.

Entry: `FeedPipeline` → `AutoSource#articles` → `Scraper.build_instance` → per-scraper extraction → `Cleanup`.

## Live flow

1. **Request** — `RequestSession` returns a `Response` with `body` (String) and `parsed_body` (Nokogiri HTML, or parsed JSON for JSON media types). Direct syndication responses skip HTML scrapers and parse via `Syndication::Parser`.
2. **JSON document body** — When the response is a JSON media type (`Response#json_response?`), AutoSource runs `JsonDocument` only (no HTML tiers). Scalar JSON is `unsupported_surface`. Same-domain Cleanup stays on by default (`keep_different_domain: false`). If the scraper yielded items and Cleanup kept none, `Log.warn` emits `auto_source.admission_emptied` with drop tallies; a `different_domain` tally hints at `auto_source.cleanup.keep_different_domain: true` / `--keep-different-domain`, which lets the remote source control off-domain link targets (no affiliation or safety check); a `sponsored` tally hints at `auto_source.cleanup.keep_sponsored: true` / `--keep-sponsored`. Guidance stays in help/docs and that structured warning — stdout feed output stays composable.
3. **Scraper tiers** (HTML only) — Enabled scrapers that claim the page (shallow `articles?` or instance `extractable?`) run in `Scraper::SCRAPER_TIERS` order. Merge within a tier, then stop when `limit` counting articles survive Cleanup. Every admitted item counts except a media item (`Article#media?`: a Schema `VideoObject`, `AudioObject`, `PodcastEpisode` or `Clip`, standalone, in `@graph` or an array, or an ItemList element) on a page that is no media page, and a structured item the page does not show in its content (`Corroboration#shown?`: a `CORROBORATED_SCRAPERS` item kept by score, not rendered as a content anchor); both stay admitted but never stop the tiers, and the final cap to `limit` takes counting items first, then fills with the rest. A media page (`Corroboration#media_page?`: more than half of the items read off the page and shown in its content are media, each article identity counted once, such as a podcast's episode list) counts its media items and puts them first: media items, then the other counting items, each group in the document order of its content anchors (`Corroboration#page_order` over `PageLinks#content_position`, from the placement walk), not tier order. A page is judged a media page only after a heuristic tier has read its cards. A native feed's items come first and the page tiers still run to fill up to `limit`; a page copy of a feed article merges into the feed item (below):

   0. Native feed: NativeFeed (head alternates + path discovery → RSS/Atom/RDF parse); what the feed states about its channel (author, iTunes categories, explicit flag) is kept as `AutoSource#feed_channel` for `Channel` (`CONTEXT.md` § Channel), and where it was read (`NativeFeed#feed_url`) for Cleanup's domain rule. A link-less feed item takes its guid when that is an absolute http(s) URL, else its first audio or video file (`Syndication::Parser`)
   1. In-page structured: Schema, Microdata, Microformats2, JsonState, XhrArticles
   2. Follow-up IO: WordPress API, Sitemap, MetaOembed
   3. Heuristic: SemanticHtml
   4. Heuristic: Html (skipped when earlier tiers already admitted at least one clean article)

4. **Structured / API scrapers** — Schema, Microdata, MF2, JSON state, XHR JSON, oEmbed, WordPress REST, and Sitemap work on Nokogiri CSS/XPath or JSON/XML parsers. They do not extract from SST. `JsonDocument` walks a JSON response body (JSON Feed mapping or `JsonState.discover_articles`).
5. **Heuristic scrapers** — `SemanticHtml` and `Html` share the page `SST::Document` (built lazily, at most once per page, by the first consumer: a heuristic tier or the page check), then:

   `SST::Normalizer` → `AutoSource::Segmenter` → `Scoring::Engine` → extractor / article materialization.

6. **Cleanup** — Page-check structured items, merge copies of one article (`PageLinks#identity`: `Url#article_identity` less the page's placement params) into one item (the first copy keeps every field it carries — a native feed item its date, guid, description, publisher title, declared media files and image, even when the page card's image is larger — and later copies fill only the fields it lacks, such as the page card's image when the feed item has none, or categories, via `Article#merge`), drop explicitly sponsored items of every source, drop items linking off the page's domain (unless `keep_different_domain`; a followed native feed's own items may also link to that feed's domain, such as a podcast platform's episode pages; an item whose URL is its own audio/video enclosure, a link-less episode served from a CDN, skips the rule), hard-exclude non-article destinations (via `PathClassifier` facts), drop untitled page-derived items (`blank_title`; publisher feeds may carry untitled posts), titles under three words (`WordCount`: unspaced Japanese or Chinese text counts one word per six characters) and junk titles, and trim to `limit`. Titles from the heuristic scrapers (`Scraper::HEURISTIC_SCRAPERS`) reach Cleanup composed by `Article::Title` (`Kicker: Headline` read from elements by `Html::TitlePieces`: kicker leaves in or beside the heading, the headline piece of an element-only heading or anchor or its `data-title`, and no date, time, duration, concealed, lead or trailing tag elements, nor teaser clock, label or type noise in en, de, fr, es, it, nl, pl, sv and ja; a Japanese leading `【…】`/`＜…＞` is dropped when it names a content type and is the kicker otherwise); every other scraper carries a publisher-declared headline (structured data, feeds, APIs) and keeps it verbatim apart from whitespace collapse and invisible characters (soft hyphens, zero-width characters). Cleanup rejects junk titles but never rewrites them. Html is skipped when earlier tiers already admitted clean items.

   Page check: items from `Scraper::CORROBORATED_SCRAPERS` go through `Corroboration#verdict` before dedupe. `PageLinks` places each URL on the rendered page (content, peripheral, chrome, absent). Content keeps; chrome-only drops as `chrome_only`; unrendered drops as `not_on_page` when the page renders at least half of the item's scraper cohort (or the cohort has fewer than three items), otherwise it is scored with absence counting against it; peripheral items, and any item on a sparse page or a JSON response (no page), keep only on a private article-likeness score, else `unlikely`. Dropped items never count toward tier stop, so the heuristic tiers run and merge; `PageLinks` keys URLs by `PageLinks#identity` (`Url#article_identity`: ignores scheme, fragment, trailing slash, and tracking query params, plus the page's placement params; other params stay significant), the same key Corroboration and Cleanup use. A placement param (`?pos=top` and `?pos=latest` placing one story twice) is decided by evidence on the page, not a name list: `PageLinks::PlacementParams` finds a param carried by at least `MIN_PATHS` distinct content-link paths where at least `MIN_REPEATED_PATHS` of them appear under two or more of its values with every other query pair equal, so a param on one path only (`/news.php?id=1`, `?id=2`) stays significant. Cleanup drops those params from every kept item URL. A kept structured item whose URL differs from its rendered content anchor only by those takes the anchor's URL minus tracking and placement params, never downgraded from `https` to `http`, so the item guid stays stable (`PageLinks#canonical_url` via `Corroboration#canonical_url`), so it merges with the heuristic copy; for a shared URL the kept structured copy wins dedupe.

   Sponsored items: `PageLinks` marks a URL sponsored when every card linking it carries a `LinkDestination::Sponsorship` marker. A container marker (`rel="sponsored"`, a truthy `data-sponsored`/`data-advertorial`, a sponsored or native-advertising class token such as `card--sponsored` or `adv-native-strip`, or an ARIA ad label) marks every destination inside it; a label inside a card link marks that link's destination across its one-card unit; any other label (an ad-label class, or a standalone element whose whole text is an ad word such as "Anzeige" or a paid phrase such as "Sponsored by …") marks the headline destination of the `article`, `section`, `aside` or `li` it sits in; and a paid phrase outside every anchor binds at its first ancestor holding a destination: the one card it sits in alone (bare `div` cards included) is marked, and so is every card of a section whose header it is (a heading, a `header` element or a header box), never from plain text before the cards. Label words in headlines, anchor text or prose, ad words on topic chips, and unpaid attribution ("Presented by …"), never count. Cleanup drops such items from every source as `sponsored`, a native feed's paid post included; `auto_source.cleanup.keep_sponsored: true` keeps them, titled without the paid label. Rules: `CONTEXT.md` § Sponsored items.

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

Precision and recall changes are measured on the labeled corpus (`bin/auto-source-corpus`, ratchet spec, `make corpus-baseline`); see `CONTEXT.md` § Auto-source corpus. Wall/alloc budgets: `make perf-baseline` (auto-source), `make perf-baseline-selectors`, `make perf-baseline-feed` (native-feed parse, RSS/JSON Feed render, descriptions); `make perf-check` gates all three (`bin/lib/perf_baseline.rb` owns the 1.15x allocation rule). Revision-to-revision effect on saved real pages: `bin/compare-revisions`.

## Non-goals

- Replacing Selectors, Schema, Microdata, MF2, JsonState, JsonDocument, or XhrArticles with SST.
- Turning `keep_different_domain` on automatically for JSON documents (operators must opt in explicitly; the flag trusts the source for any published link domain).
- A second HTML parser beside Nokogiri.
- Dual Response payload (Nokogiri + SST always).
- App-shell classification on SST.
- Rewriting Sanitize transformers off Nokogiri.

See also {file:CONTEXT CONTEXT.md} for module ownership (chrome, scoring, clustering), {Html2rss::FeedPipeline} for the request-strategy fallback chain (unrelated to article scraping), and {Html2rss::Capture} to turn a listing URL into a durable items-selector config.
