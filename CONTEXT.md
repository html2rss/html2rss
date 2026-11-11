# Context

Contributor map for request, AutoSource, and selectors seams.

## Native feed preference

Same-origin RSS/Atom preference for curation gates (Capture defer/`--force`, Recon `:defer`).
Owned only by `Syndication::Discovery.best_feed_url` (head alternates + path probes via session).
`PageRecon` may still expose `alternate_feeds` for Inspect diagnostics — that list is not a second preference algorithm.

## Frozen contract

Parallel curation work shares this vocabulary. User/agent surfaces (CLI, MCP, `next_step`, docs) use **seven verbs only** — no `_url` / `_config` suffixes on wire names.

### User-facing verb table

| Verb     | Job                   | Domain                   | CLI      | MCP      | Facade                             |
| -------- | --------------------- | ------------------------ | -------- | -------- | ---------------------------------- |
| inspect  | Diagnostics           | `PageRecon::Diagnostics` | inspect  | inspect  | `Html2rss.inspect`                 |
| recon    | Verdict + native_feed | `Recon`                  | recon    | recon    | `Html2rss.recon`, `.batch_recon`   |
| capture  | YAML draft            | `Capture`                | capture  | capture  | `Html2rss.capture`                 |
| validate | Schema only           | `Config`                 | validate | validate | `Html2rss.validate`                |
| test     | Schema + live         | `Test`                   | test     | test     | `Html2rss.test`                    |
| apply    | Ship RSS              | `feed_result`            | apply    | apply    | `Html2rss.apply`                   |
| scrape   | Articles now          | `auto_feed_result`       | scrape   | scrape   | `Html2rss.scrape`, `.batch_scrape` |

Batch variants: `batch_inspect`, `batch_recon`, `batch_scrape` (CLI/MCP/facade — same bare prefix, no `_urls` suffix).

CLI historic aliases: `feed` → `apply`, `auto` → `scrape` (Thor `map` only — canonical names unchanged).

**Golden path:** optional **inspect → recon → capture → test → apply**. Side door: **validate**. One-shot: **scrape**.

### Wire vs internal

Pipeline internals keep existing names — do not rename `Html2rss.feed` / `feed_result` in pipeline specs or `spec/examples/`.

| Internal API                              | Role                       | User-facing verb      |
| ----------------------------------------- | -------------------------- | --------------------- |
| `Html2rss.feed` / `feed_result`           | Build RSS from config Hash | **apply**             |
| `Html2rss.auto_feed_result`               | Auto-source from URL       | **scrape**            |
| `Html2rss.auto_source` / `auto_json_feed` | Lower-level auto helpers   | used by scrape facade |

CLI/MCP **`apply`** calls **`feed_result`**; **`scrape`** calls **`auto_feed_result`**. Facades delegate — they are not renames of pipeline entrypoints.

### File ownership matrix

| Path                                                                                              | Owner wave        |
| ------------------------------------------------------------------------------------------------- | ----------------- |
| `lib/html2rss/page_recon/diagnostics.rb`, `batch.rb`                                              | Wave 1            |
| `lib/html2rss/mcp/**`                                                                             | Wave 2 Agent MCP  |
| `lib/html2rss/cli.rb`, `lib/html2rss.rb` (facades section)                                        | Wave 2 Agent CLI  |
| `spec/lib/html2rss/cli_spec.rb`, `html2rss_spec.rb`                                               | Wave 2 Agent CLI  |
| `spec/lib/html2rss/mcp/**`                                                                        | Wave 2 Agent MCP  |
| `spec/lib/html2rss/page_recon/diagnostics_spec.rb`                                                | Wave 1            |
| `AGENTS.md`, `README.md`, `CONTEXT.md`, `lib/html2rss/*/README.md`, `mcp.rb` YARD | docs |
| `spec/integration/curation_golden_path_spec.rb`                                                   | Wave 3 Integrator |

### Factory signatures

```text
PageRecon::Diagnostics.call(url:, strategy:) → Report
PageRecon::Diagnostics.batch(urls:, ...) → [Report]
Batch.batch_inspect / batch_recon / batch_scrape
Html2rss.inspect / .apply / .scrape / .batch_scrape / .batch_inspect / .batch_recon
Outcome::Playbook.instructions, Outcome factories typed, Tool.title on MCP::Server::Tools::Tool, NextStep::ALL / Playbook::GUIDANCE keys == verbs
```

Instruction prose SSOT: `Outcome::Playbook`. Module guide: `lib/html2rss/mcp/README.md`.

## Curation CLI / MCP

Composable curation seams for inspect → recon → capture → validate/test → apply:

| Fact                                      | Owner                                                                                                                                                                                                                         |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Diagnostic URL fetch + assess             | `PageRecon::Diagnostics` (uses `PageRecon.probe` → `PageRecon::Probe` for fetch; adds scraper/XHR diagnostics). Module guide: `lib/html2rss/page_recon/README.md` (redirect follow; no default `Host` — HTTPX sets per hop) |
| Curation verdict                          | `Recon::Verdict` on `Recon::Result` (`:build` / `:defer` / `:drop`)                                                                                                                                                           |
| Native feed URL (defer/gate)              | `Syndication::Discovery.best_feed_url` only                                                                                                                                                                                   |
| Config Hash/path/YAML → validated raw     | `Config.resolve_and_validate` → `Config::ValidationReport` (`issues` only; Dry stays internal)                                                                                                                                |
| Validate + live + min_items + RSS         | `Test` → `Test::Result` (+ `FailureKind`, success carries `rss`)                                                                                                                                                              |
| MCP next_step / guidance / playbook prose | `MCP::Outcome` + `Outcome::Playbook` (bare verb `next_step` names)                                                                                                                                                            |
| Capture YAML product                      | `Capture::CaptureResult#yaml` only (facade `Html2rss.capture` returns `CaptureResult`)                                                                                                                                        |
| Batch concurrency                         | `Batch.map` Thread pool (not Ractors); preserves input order (`Recon.batch`, `Batch.batch_*`, MCP)                                                                                                                            |

`apply` zero-item ship gate stays distinct from `Test` min_items. **inspect ≠ recon:** inspect is cheap diagnostics; recon adds verdict and native_feed preference.

## Scrape target

Immutable entry vs effective fetch URL for one pipeline run. Owned by `Html2rss::ScrapeTarget` — constructed from `Config#url`, sticky-updated only when `FeedResolution.try_apply!` returns `:succeeded` (retry extract yielded items). Tournament wins with an empty retry leave `effective_url` on the entry URL so later auto-fallback strategies do not inherit a failed rewrite. `RequestSession.build` accepts an optional `scrape_url:` override. `Config` stays unchanged.

## Page assessment

Cheap surface class and admitted article count for probe scoring. Owned by `PageRecon::Assessment` via `PageRecon.assess` (fixed AutoSource limit). Empty-extract error labels use `PageRecon.surface_category_for` (classify only — no second AutoSource). Full pipeline extract counts stay on `FeedPipeline#deduplicated_articles`; tournament policy uses that typed `articles:` array.

Diagnostic URL fetch for curation inspect and recon is owned by `PageRecon::Diagnostics` (via `PageRecon.probe` → `PageRecon::Probe`: `session`, `response`, `result`, `strategy`).

## Syndication candidate catalog

Shared path lexicon for native feed discovery and entry-resolution listing guesses. Owned by `Syndication::CandidateCatalog` (`FEED_PATHS`, `LISTING_PATHS`). `Syndication::Discovery` and `FeedResolution::CandidateGenerator` consume it.

## URL document identity

Trailing-slash and fragment-insensitive same-document compare. Owned by `Html2rss::Url#same_document?`. `FeedResolution::CandidateGenerator` filters with it. Differs from `Url#==` (slash-sensitive).

## URL article identity

Scheme-, fragment-, trailing-slash-, query-param-order-, and tracking-param-insensitive "same article" key (closed `Url::TRACKING_PARAM` set: `utm_*`, `fbclid`, `gclid`, `msclkid`, `mc_cid`, `mc_eid`, `ref`, `ref_src`; every other query param stays significant). Owned by `Html2rss::Url#article_identity`; `AutoSource::PageLinks` keys rendered anchors by it and `Cleanup` dedupes, rejects self-links, and audits URL diversity by it, so one rule decides all. A kept corroborated item whose URL differs from its content anchor only by these takes the anchor's URL minus tracking params (`Url#without_tracking_params`), never downgraded from `https` to `http`, so the item guid stays stable (`PageLinks#canonical_url`, applied by `Cleanup`).

## Feed resolution policy

Whether the entry URL tournament runs. Owned by `FeedResolution::Policy` — requires typed `articles:` Array (`ArgumentError` otherwise; derive count from `articles.size`), surface weak/blocked predicates, and NativeFeed ≥50% majority (`scraper == AutoSource::Scraper::NativeFeed`).

## Feed resolution candidates

Same-origin probe URL mix for the tournament. Owned by `FeedResolution::CandidateGenerator`: one Discovery feed slot + up to `max - 1` listing URLs (taxonomy-first nav → segment first-wins `:list` → `:cluster` → `:semantic` → `LISTING_PATHS`). Listing seeds stay in that mix; a concatenated list truncated with `.first(max)` drops them.

## Feed resolution scoring

Probe score weights, drop penalties, and winner pick for the entry URL tournament. Owned by `FeedResolution::Scorer`. `FeedResolution::Probe` fetches via `PageRecon.assess` (not fat `PageRecon.call`).

## Surface category

Closed surface class for no-scraper / assessment gates. Owned by `Html2rss::SurfaceCategory` (`weak?` / `blocked?` / `listing_bonus?`). `PageRecon::Assessment` exposes those predicates; `FeedResolution::Policy` and `Scorer` call them.

## Entry-resolution options

Typed `auto_source.entry_resolution` expansion. Owned by `FeedResolution::Options` (`enabled?`, `max_probes`, `request_slots`). Policy eligibility, Runner probe caps, and budget slot reservation consume it.

## Pipeline outcome URLs

`FeedPipeline::PipelineOutcome` carries `ScrapeTarget` plus optional `FeedResolution::Diag`. `Status.build` maps to wire `entry_url` / `scrape_url` / `entry_resolution` Hash. `Diag.applied: true` means the tournament picked a winner; it does not mean wire `scrape_url` changed. Only `Status` `scrape_url` / `ScrapeTarget.effective_url` reflect a sticky rewrite after a successful retry.

## Request Budget

Shared wall-clock and HTTP request meters for one feed build. Constructed via `RequestSession::RuntimePolicy.resources_for(config)` (policy + budget from one expansion); `budget_for` remains a thin alias. `FeedPipeline` builds sessions with `RequestSession.build` (Context normalizes once). `RequestService::Context` requires an explicit `budget:`. Adapter attempt timeouts resolve through `Budget#effective_timeout_seconds` / `#effective_timeout_ms`. Auto fallback run state lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext`.

## HTML-ness

`RequestService.response_cache=` is an opt-in seam for initial fetches (`RequestService::ResponseCache`: TTL, bounded, 2xx only; key is a digest incl. `Policy#cache_key`). Only the MCP process installs it (default 300s, `HTML2RSS_RESPONSE_CACHE_TTL`; `0`/`off` disables); hits surface as `Response#cache_age` and the envelope `cache` field (MCP contract v4). The seam lives in `RequestService::ResponseCaching`; the cache is also bounded to 32 entries / 32 MiB.

Whether a response document is HTML is owned by `RequestService::Response#html_response?` (Content-Type `text/html`, or a non-JSON body matching `Response::HTML_BODY_SNIFF`). `content_type` stays the wire header. Capture, Channel, and curation inspect all call that one predicate. Gzip/brotli inflate stays on `CompressedBody`, called only from the HTTPX adapter.

## Botasaurus scrape contract

OpenAPI 2.0 `ScrapeRequest` / `ScrapeSuccess` / `ScrapeError` is the wire authority. CI locks client constants against `spec/fixtures/botasaurus/openapi.yaml` (vendored sibling snapshot); when `../botasaurus-scrape-api/openapi.yaml` is present locally, specs assert the fixture still matches. Closed sets, wait bounds, request option keys, and `window_size` `{width, height}` live on `RequestService::BotasaurusContract`. `Config::Validator::BotasaurusRequestConfig` consumes those constants for YAML admission (`scroll` is scroll-to-bottom). `BotasaurusStrategy` is HTTPX `POST /scrape` plus gem error mapping: 200 → `Success`; 4xx/5xx → `Error` (`challenge_block` → `BlockedSurfaceDetected`, `timeout` / 504 → `RequestTimedOut`, otherwise `BotasaurusServiceError`). **Transport hop** (HTTP to scrape-api, not JSON body): `User-Agent` = `RequestHeaders::DEFAULT_USER_AGENT`, `Accept-Encoding: identity`, per-execute `X-Request-Id`. Target headers stay in `ScrapeRequest.headers`. scrape-api honors inbound `X-Request-Id` for all `diagnostics.request_id` envelopes. `Response#transport_meta` is `diagnostics` plus success-only `metadata_error`.

## DOM chrome

Layout noise and primary-link recognition for the **manual selector** path: ignored container tags/paths, class-clustering exclusions, utility landmarks, heading tags, main-anchor CSS, and visible-text extraction. Owned by `Html2rss::Html::Navigator` (+ `TextExtractor`); its tag sets and skip-href prefixes derive from `SST::Tags`, the single vocabulary owner. `Html::ArticleExtractor` serves selectors only.

Heuristic auto-source chrome lives on `SST::Tags` / `SST::Text` after `SST::Normalizer` (sole Nokogiri on that path). `SST::Index#ignored_chrome?` is set by the Normalizer: `nav` (and stripped tags) are chrome anywhere; `header`/`footer` (`Tags::PAGE_CHROME_NAMES`) are chrome only at page level, not under `Tags::SECTIONING_NAMES` (`article`/`section`/`aside`/`main`), matching ARIA banner/contentinfo scoping, so card permalinks in `<article><header>` stay content. Chrome is inherited: a header under `nav` or a page-level footer stays chrome. `Navigator.usable_card_parent?` applies the same scoping to card walks (SST nodes read `ignored_chrome?`; Nokogiri nodes check for a sectioning ancestor). A card kicker is passed to `Article` apart from the headline: `Html::TitlePieces` excludes `time` and noise pieces of the kicker (`Article::Title.noise_piece?`: clock, field label such as `Section:`, type marker); see § Article title.

## Default items selector

The wire spelling is owned by `Html2rss::Selectors::DEFAULT_ITEMS_SELECTOR`. The runtime CSS that spelling expands to is owned by `Html::Navigator::MAIN_ANCHOR_SELECTOR`. `Config.prepare_defaults` merges the default only when `selectors:` is present. Auto-source-only configs stay selector-free. An explicit selector, including `a` or `.card`, is not rewritten.

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking signals. Owned by `Html2rss::Scoring::Engine` (+ `ContainerAssessor`). `LinkResolver` owns token regexp derivation from `PathClassifier::SEGMENT_SETS` (`CONTENT_TOKEN_REGEXP` / `JUNK_TOKEN_REGEXP`); ContainerAssessor consumes those defaults (or injected regexps). Rank-time hard drops live on `Scoring::Observation#hard_junk?` (container assessment — not content-anchor eligibility). `SemanticHtml` / `Html` orchestrate Normalizer → Segmenter → Scoring → `Html::SstArticleExtractor` only. Scrapers supply one page-scoped `Scoring::LinkResolver` into Segmenter, Engine, and SemanticHtml dedup.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned by `Html2rss::LinkDestination::NoisePolicy`. Utility-landmark ancestry is computed by `AutoSource::Segmenter#landmark_ancestor?` and injected as `utility_landmark_ancestor:` — NoisePolicy does not walk `SST::Index`. Primary-link ranking weights are inlined in `Segmenter::PrimaryLink#candidate_facts`. Feature ids and `Score`/`RankedSegment` factories live on `Scoring::Engine`. Segmenter discovers candidates and may _call_ NoisePolicy; it does not own eligibility weights. Scrapers pass the page `LinkResolver` into Segmenter so DestinationFacts memoization stays local to the page run.

## Feed-item admission

Whether an extracted candidate may become a feed item. Owned by `Html2rss::AutoSource::Cleanup` (scheme/domain/self-link/title floor, destination-class hard exclude, sponsored items, **and** the structured-tier page check). Destination facts come from `LinkDestination::DestinationFacts` / `PathClassifier` — Cleanup does not own path lexicon Sets. Title string backstop stays `Cleanup.junk_reason` only. Scoring may demote or rank-time drop for heuristic discovery; it does not admit feed items. `AutoSource` short-circuits Html when earlier tiers already admitted ≥1 clean article below `limit` (quality over padding). Tier stop counts Cleanup-admitted items only, so items the page check drops never stop later tiers.

## Structured-tier corroboration

Whether an in-page structured item is backed by the rendered page. Which scrapers are checked: `AutoSource::Scraper::CORROBORATED_SCRAPERS` (Schema, Microdata, Microformats2, JsonState, XhrArticles, JsonDocument); native feed, CMS REST API, sitemap, and oEmbed items are publisher-declared and exempt. Where a URL is rendered: `AutoSource::PageLinks` (one pass over SST anchors keyed by `Url#article_identity`; `:content`, `:peripheral` for aside/menu/sectioned-footer landmarks, `:chrome` from `SST::Index#ignored_chrome?`, else `:absent`; `#sparse?` for no page, a degraded SST, or at most two content URLs). The keep/drop verdict and its private article-likeness score (dates, image, description, URL shape, scraper-cohort size and parent-path cohesion): `AutoSource::Corroboration#verdict`. Content placement keeps; chrome-only and unrendered URLs drop (`chrome_only`, `not_on_page`) unless the page is sparse; peripheral and sparse-page items keep on score, else drop as `unlikely`. Absence drops only when the page renders the item's scraper cohort (at least half of it as content anchors, or fewer than three items); a cohort the page mostly does not render (app shell with consent or legal links, aggregator redirect anchors) is scored with absence counting one against it. A shallow path ending in a post slug is a root-level permalink, not a section root. Cleanup runs the check before dedupe and tallies the reasons, so a dropped structured copy leaves its URL to a heuristic tier and a kept one wins dedupe. `AutoSource` memoizes the SST and page `LinkResolver` lazily: the first consumer (page check or heuristic tier) builds them, at most once per page. JsonState keeps no chrome rules of its own.

## Sponsored items

Whether an item is explicitly sponsored. Marker vocabulary owned by `Html2rss::LinkDestination::Sponsorship.marker`, in two kinds. **Container** markers state that an element is paid content: a `rel` token `sponsored`, a `data-sponsored` / `data-advertorial` value from the closed truthy set (`true`, `1`, `yes`; an empty value, bare attribute, `no`, `null`, `false`, `0` or `off` is off), a sponsored or advertorial class token (whole, BEM `card--sponsored`, `is-sponsored`, `sponsored-content`; never `unsponsored`), or an ARIA label that is an ad label. **Label** markers are an ad-label class token (`ad-label`, `ad-badge__item`) or a standalone element whose whole text is one clearly paid label from a closed multilingual set (en, de, fr, es: "Sponsored", "Anzeige", "Werbung", "Publicité", "Publicidad", "Advertorial", "Paid content", "Ad", …); paid attribution ("Sponsored by …", "Gesponsert von …", "Sponsorisé par …", "Patrocinado por …") may name the sponsor in up to five words. Attribution that states no payment ("Presented by", "Präsentiert von", "In Kooperation mit", "En partenariat avec") is no label. A class or text label counts only on a rendered element (no `hidden` attribute, `display:none` or hiding utility class `hidden` / `d-none` / `is-hidden` / `hide`); `aria-hidden="true"` (a visual label) and screen-reader-only classes (a spoken label) still count. A class marker also needs content. A text label never counts inside running text: not on or inside an anchor or heading, not on a topic chip (category, tag, kicker class), not in an inline element of prose, and not when the element holds other text (a meta line). Anchor text, item titles and URL paths are never read. `SST::Normalizer` keeps `rel`, `hidden`, `data-*` and `aria-*` in `Attrs#raw` for it. `AutoSource::PageLinks` scopes each marker in one walk: a container holding anchors marks every destination inside it. A label (or anchorless container) marks only the card it sits in: its nearest `article`, `section`, `aside` or `li` (the marked element itself included; `main` is a page region, never a card). That card marks its dominant destination: its only destination, else its only headline destination (an anchor in or around a heading), so secondary image, tag or sponsor links do not hide the card while a card with several headlines marks nothing. Labels never climb: a label outside every card (bare `div` layouts, an ad slot beside a teaser in a row) binds nothing, accepting a missed ad over a lost story. Marking is per card: a URL is sponsored (`#sponsored?`) only when every anchor to it sits inside a marked card, so a promo slot never hides the editorial card linking the same story. PageLinks walks lazily: `#sponsored?` walks markers and resolves only the anchors of marked cards, then, when any card is marked, the remaining anchors once; placement, canonical and sparse checks resolve every anchor on first use. Cleanup drops sponsored items from page-derived scrapers (`CORROBORATED_SCRAPERS` and the heuristic tiers) after dedupe, tallied as `sponsored`; publisher-declared sources are exempt. `auto_source.cleanup.keep_sponsored: true` keeps them. Known gaps (accepted misses): a linked label (`<a class="label">Anzeige</a>`), German topic-chip class words, bare-`div` ad cards.

## Auto-source corpus

Labeled synthetic pages under `spec/fixtures/auto_source/corpus/` (hosts `example.com` only); each page (`.html` or `.json`) has a `.yml` sidecar listing its expected article URLs. `AutoSourceCorpus` (`spec/support/auto_source_corpus.rb`) is the sole runner: fixed base URL, no request session, no network. It scores admitted URLs per page as junk (not in the sidecar) and real (in the sidecar), and reports whether `SST::Normalizer` ran (observed by a spec-side probe, not a `lib/` hook). `bin/auto-source-corpus` prints the table. `auto_source_corpus_spec.rb` ratchets against `corpus/baseline.yml`: it fails only when a page's junk rises or real-found drops. Re-record intended changes only via `make corpus-baseline`. A sidecar may also carry a `titles:` map (expected URL to exact title); the table's `title_miss` column counts titles the admitted article does not carry verbatim, and the ratchet fails only when that count rises. Adding a page means adding its sidecar and re-recording.

`bin/compare-revisions BASE HEAD --pages DIR [--limit N]` (`make compare-revisions`) compares two git revisions on saved pages kept outside the repo. `DIR` holds the pages plus a `manifest.tsv` of `<file><TAB><base url>` lines (`#` comments allowed); `--limit` keeps the first N entries. Each revision runs in a detached temporary worktree (removed on exit) with its own `lib/` and Gemfile.lock gems; pages run offline through `AutoSourceCorpus.auto_source` (the one runner). The report lists per page item counts, items lost and gained, title changes, Cleanup drop tallies and wall time, then a totals line. Diff and report logic lives in `spec/support/revision_comparison.rb` (`RevisionComparison`), covered by its spec. The tool never writes into the repo.

The synthetic `title_*` and `sponsored_*` pages record the #574 gaps (spaced-colon kicker, block elements in a heading, clock prefixes, non-English type markers, ad-labelled and `rel="sponsored"` cards, and an advertising story that must be kept). Their baseline rows are the failing starting point the title and sponsored phases ratchet down; the `title_*` rows are at 0 title misses since § Article title landed.

## Article title

Owned by `Html2rss::Article::Title`. Whitespace collapse (newlines included, `Title.collapse`) is universal: `Article#initialize` applies it to every title. Composition (`Title.compose`: `Kicker: Headline`, noise stripping) is opt-in per caller via `Article.new(compose_title: true)`; the default keeps the title verbatim. Opt-in callers: `Html::SstArticleExtractor`, which reads the cards of the heuristic scrapers (`Scraper::HEURISTIC_SCRAPERS`: `SemanticHtml`, `Html`); they yield composed `Article`s. Every scraper that yields Hash items carries a publisher-declared headline, so `AutoSource` builds those collapse-only: structured in-page data (`Schema`, `Microdata`, `Microformats2`, `JsonState`, `XhrArticles`, `JsonDocument`), publisher endpoints (`NativeFeed`, `WordpressApi`, `Sitemap`, `MetaOembed`), configured `selectors` titles and syndication items (`FeedPipeline`) stay verbatim, so a real headline `10:00 Budget vote` or `Video: ...` survives. (`Scraper::PAGE_SCRAPERS` is the sponsorship split only.) Scrapers pass `title:` (the headline) and, when the source exposes one, `kicker:`; Article stores only the result (`kicker` is not in `PROVIDED_KEYS`, so it is no selector key, and it is ignored without `compose_title`). Composition collapses whitespace, trims stray separators from both parts (one constant set, `Title::SEPARATOR_MARK`: `: | • · – — - / > » › →`, each a leading separator only when whitespace follows, so a sign `–5 Grad`, a path `/e/` or a German `»quote«` is not one, nor `>` before a number (`> 50 Prozent`); trailing, `: | • · – —` always and `- / > › →` after whitespace, while a trailing `»` closes a French quote and stays), so a headline opening with a separator after the kicker (`Kicker</span> – Headline`) and a kicker ending in one (`Kicker -`) both give exactly `Kicker: Headline`. It normalizes an inline kicker boundary (`Kicker : Headline` → `Kicker: Headline`, only after at most eight words ending in a letter or closing quote/bracket, so `16 : 9` keeps its colon), and drops a kicker that is blank, a type marker, or already opens the headline as a whole word (a headline that only mentions it further in keeps it). When the headline is blank, the kicker alone is the title (Cleanup's title floor then judges it). Headline text is never noise-stripped by text rules: `16:10 laptops…`, `23:21 – Handball…`, `20:15 Uhr: Neuer Krimi…`, `9:41 is…` and `12:00 noon…` stay verbatim, because the string cannot tell a timestamp from headline words. Noise is one closed multilingual (en, de, fr, es) vocabulary on `Article::Title`: valid clock times (`CLOCK`, `00:00`–`23:59`, so a score `28:25` is never a clock), field labels (`Section:`, `Rubrik:`, `Rubrique :`, `Sección:`), and type labels with their marker (`Article type: Video`, `Artikeltyp: Video`). It applies to the kicker as text (a leading clock set off by a separator, labels) and to standalone elements. Element rules are owned by `Html::TitlePieces`, the one kicker and headline reader both extractors call (SST and Nokogiri nodes), so both give one title for the same markup: a `time` element or an element whose text is only a clock or only a label (`Title.headline_noise_piece?`) is dropped from headline text only before its first word (`<time>19:47</time> Coalition…` loses the clock; `leaves at <strong>20:15</strong> from…`, `moved to <time>Friday</time>` and `<em>Category:</em>` mid-sentence stay), and each kicker piece is judged with `Title.noise_piece?` (blank, clock, field label ending in `:`, type marker). `ArticleRules::Description` reuses `CLOCK_PIECE` (`Title.clock_piece?`, chip peeling) and `TYPE_MARKERS` (as `TYPE_CHIPS`) and keeps only description-specific sets (CTA, listing section names, date shapes). Kicker marks (`TitlePieces::KICKER_CLASS` class tokens, `data-tb-kicker`) have one owner. The kicker node is the outermost kicker-marked element that carries kicker text, stands beside the headline, and holds no word outside its noise and its kicker-marked parts. It carries kicker text when it is no noise element itself and holds a letter or digit outside its noise pieces, so an icon, clock or `time` leaf is skipped. It stands beside the headline unless it is or wraps the heading (or, without a heading, the anchor), or holds all of the heading's text. So `kicker__topic` + `kicker__sub` in a `kicker` give one kicker (`Politik Bund`), an `eyebrow-row` holding a status beside its `eyebrow` gives the eyebrow, and `kicker-group`, `headline__inner--has-kicker` and a `teaser--with-kicker` card are wrappers or modifiers, never the kicker. A kicker nested in the heading or anchor is excluded from the headline text and passed as the kicker. `Html::ArticleExtractor` is itself an opt-in caller: it returns `Article::Title.compose(headline, kicker:)` as its `title` because Selectors' enhance merges hash keys one by one and cannot tell an extracted title from a selected one; a separate `kicker` key would prefix an explicitly selected title, while the pre-composed title only ever fills an empty one and reaches `Article` verbatim. Composition is idempotent, so `with_url` and Marshal round-trips keep the title. Corpus pages `title_kicker_selection`, `title_headline_noise_placement` and `title_separators_typography` pin these rules; known gaps stay out of their `titles:` maps: an unlisted screen-reader label (`Article:`), soft hyphens and zero-width characters.

## JSON state article node

Which hashes of a JSON state entry hold its article fields. Owned by `JsonState::ArticleNormalizer.article_sources` (detector and normaliser both consult it; `ValueFinder` reads only the keys of the hashes it is given). An entry with its own title or description is the node; a wrapper entry delegates to the only nested Hash (up to two levels) with title and URL, else the only titled one, keeping the entry as fallback source; competing nodes skip the entry. An entry with its own direct URL (not the envelope `links` key) delegates only to a node with a real title key (`title`/`headline`/`text`, never a bare `name`) and keeps its URL; an entry whose only URL is `links` keeps the node first. No wrapper-key list.

## Enhance leftover fields

Visible leftover after excluding heading/anchor/kicker/`time` is split once on block newlines. Keep/drop (CTA, date-shaped, field labels, type chips, title echo, listing section names) is owned only by `Html2rss::Html::ArticleRules::Description`; its type chips and clock shape come from `Article::Title` (§ Article title). Title echo compares against the headline. Dates stay on `ArticleRules::Date` (datetime attrs + date-shaped leftover lines, channel `time_zone`; invalid identifiers fall back to UTC so extract does not raise). Categories stay on `ArticleRules::Category` (class tokens, not layout `label`/`section` substrings) and reject Description keepers except type chips, which are leftover chrome rather than taxonomy. Both `Html::ArticleExtractor` and `Html::SstArticleExtractor` call those modules.

## Leftover parent-card walk

When a heading-only item or wrapping `<a>` lacks leftover description and date, extractors climb via `Navigator.parent_until_condition` / `SST::Index#parent_until`. Walk policy (`miss?` / `thin_wrapper?` / `crowded?` from heading count + distinct main hrefs) is owned by `Html2rss::Html::CardWalk`. Adapters still traverse. Capture's items-selector lift is a second job: it shares only `Navigator.usable_card_parent?` stop tags and aborts with `contains_other_root?` (listing-root set).

## DOM candidate clustering

Anchorless/classless card discovery is owned by `AutoSource::Segmenter` (`:cluster` strategy). Cluster sets each card's primary link via `PrimaryLink`. Group ranking weights live in `Scoring::ClusterScorer`. Sitemap discovery remains `AutoSource::Scraper::Sitemap` (XML, not heuristic HTML).

## Channel

Feed channel metadata (title, description, ttl, language, author, image, last_build_date) extracted from the response/document with config overrides. Owned by `Html2rss::Channel`. `FeedBuilder::Rss` and `FeedBuilder::JsonFeed` are format adapters that consume Channel + Article.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for` (e.g. `rel_next` → `Pager::RelNext`).

## Extractor / post-processor registry

Module guide: `lib/html2rss/selectors/README.md`.

Extractor and post-processor names live in `Selectors::Extractors::NAME_TO_CLASS` and `Selectors::PostProcessors::NAME_TO_CLASS`. Each strategy owns config-facing options as an `OPTIONS` Array of `Selectors::OptionSpec` (name, type, required). `Config::SelectorsValidator::Selector`, `Selectors::OptionSpec.for` / `expectation_for`, and `Selectors::SchemaExport` consume that contract; post-processor `Base` enforces `OPTIONS` plus optional `VALUE_TYPE` at runtime. Extractors run as `new(xml, **config)`.
