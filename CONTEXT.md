# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Native feed preference

Same-origin RSS/Atom preference for curation gates (Capture defer/`--force`, Recon `:defer`).
Owned only by `Syndication::Discovery.best_feed_url` (head alternates + path probes via session).
`PageRecon` may still expose `alternate_feeds` for Inspect diagnostics — that list is not a second
preference algorithm. Do not reintroduce Capture `FeedLink`-only probes or Recon “first alternate” fallbacks.

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
| `AGENTS.md`, `README.md`, `CONTEXT.md`, `CHANGELOG.md`, `lib/html2rss/*/README.md`, `mcp.rb` YARD | Wave 2 Agent Docs |
| `spec/integration/curation_golden_path_spec.rb`                                                   | Wave 3 Integrator |

**Hot files (serialize or integrator-only):** `html2rss.rb`, `CONTEXT.md` when the curation contract changes.

### Factory signatures

```text
PageRecon::Diagnostics.call(url:, strategy:) → Report
PageRecon::Diagnostics.batch(urls:, ...) → [Report]
Batch.batch_inspect / batch_recon / batch_scrape
Html2rss.inspect / .apply / .scrape / .batch_scrape / .batch_inspect / .batch_recon
Outcome::Playbook.instructions, Outcome factories typed, Contract::TITLES keys == verbs
```

Instruction prose SSOT: `Outcome::Playbook`. Module guide: `lib/html2rss/mcp/README.md`.

## Curation CLI / MCP

Composable curation seams for inspect → recon → capture → validate/test → apply:

| Fact                                      | Owner                                                                                                          |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Diagnostic URL fetch + assess             | `PageRecon::Diagnostics` (uses `PageRecon.probe` → `PageRecon::Probe` for fetch; adds scraper/XHR diagnostics) |
| Curation verdict                          | `Recon::Verdict` on `Recon::Result` (`:build` / `:defer` / `:drop`)                                            |
| Native feed URL (defer/gate)              | `Syndication::Discovery.best_feed_url` only                                                                    |
| Config Hash/path/YAML → validated raw     | `Config.resolve_and_validate`                                                                                  |
| Validate + live + min_items + RSS         | `Test` → `Test::Result` (+ `FailureKind`, success carries `rss`)                                               |
| MCP next_step / guidance / playbook prose | `MCP::Outcome` + `Outcome::Playbook` (bare verb `next_step` names)                                             |
| Capture YAML product                      | `Capture::CaptureResult#yaml` only (facade `Html2rss.capture` returns `CaptureResult`)                         |
| Batch concurrency                         | `Batch.map` Thread pool (not Ractors); preserves input order (`Recon.batch`, `Batch.batch_*`, MCP)             |

`apply` zero-item ship gate stays distinct from `Test` min_items. **inspect ≠ recon:** inspect is cheap diagnostics; recon adds verdict and native_feed preference.

## Scrape target

Immutable entry vs effective fetch URL for one pipeline run. Owned by `Html2rss::ScrapeTarget` — constructed from `Config#url`, sticky-updated only when `FeedResolution.try_apply!` returns `:succeeded` (retry extract yielded items). Tournament wins with an empty retry leave `effective_url` on the entry URL so later auto-fallback strategies do not inherit a failed rewrite. `RequestSession.build` accepts an optional `scrape_url:` override; do not mutate `Config` for resolution rewrites.

## Page assessment

Cheap surface class and admitted article count for probe scoring. Owned by `PageRecon::Assessment` via `PageRecon.assess` (fixed AutoSource limit). Empty-extract error labels use `PageRecon.surface_category_for` (classify only — no second AutoSource). Full pipeline extract counts stay on `FeedPipeline#deduplicated_articles`; tournament policy uses that typed `articles:` array — do not reintroduce parallel `classify_no_scraper_surface` call sites for resolution gates.

Diagnostic URL fetch for curation inspect and recon is owned by `PageRecon::Diagnostics` (via `PageRecon.probe` → `PageRecon::Probe`: `session`, `response`, `result`, `strategy`). Do not reintroduce twin `fetch_initial` / `fetch_response` helpers in those callers.

## Syndication candidate catalog

Shared path lexicon for native feed discovery and entry-resolution listing guesses. Owned by `Syndication::CandidateCatalog` (`FEED_PATHS`, `LISTING_PATHS`). `Syndication::Discovery` and `FeedResolution::CandidateGenerator` consume it — do not duplicate path arrays.

## URL document identity

Trailing-slash and fragment-insensitive same-document compare. Owned by `Html2rss::Url#same_document?`. `FeedResolution::CandidateGenerator` filters with it — do not reintroduce string `chomp('/')` same-page compares. Differs from `Url#==` (slash-sensitive); do not change `==`.

## Feed resolution policy

Whether the entry URL tournament runs. Owned by `FeedResolution::Policy` — requires typed `articles:` Array (`ArgumentError` otherwise; derive count from `articles.size`), surface weak/blocked predicates, and NativeFeed ≥50% majority (`scraper == AutoSource::Scraper::NativeFeed`). Do not pass `articles_count:`.

## Feed resolution candidates

Same-origin probe URL mix for the tournament. Owned by `FeedResolution::CandidateGenerator`: one Discovery feed slot + up to `max - 1` listing URLs (taxonomy-first nav → segment first-wins `:list` → `:cluster` → `:semantic` → `LISTING_PATHS`). Do not concat-then-`.first(max)` (starves listing seeds).

## Feed resolution scoring

Probe score weights, drop penalties, and winner pick for the entry URL tournament. Owned by `FeedResolution::Scorer`. `FeedResolution::Probe` fetches via `PageRecon.assess` (not fat `PageRecon.call`); do not inline scoring in `Probe`.

## Surface category

Closed surface class for no-scraper / assessment gates. Owned by `Html2rss::SurfaceCategory` (`weak?` / `blocked?` / `listing_bonus?`). `PageRecon::Assessment` exposes those predicates; `FeedResolution::Policy` and `Scorer` call them — do not re-list WEAK Sets.

## Entry-resolution options

Typed `auto_source.entry_resolution` expansion. Owned by `FeedResolution::Options` (`enabled?`, `max_probes`, `request_slots`). Policy eligibility, Runner probe caps, and budget slot reservation consume it — do not dig the Hash in three places.

## Pipeline outcome URLs

`FeedPipeline::PipelineOutcome` carries `ScrapeTarget` plus optional `FeedResolution::Diag`. `Status.build` maps to wire `entry_url` / `scrape_url` / `entry_resolution` Hash — do not flatten the domain pair earlier. `Diag.applied: true` means the tournament picked a winner; it does not mean wire `scrape_url` changed. Only `Status` `scrape_url` / `ScrapeTarget.effective_url` reflect a sticky rewrite after a successful retry.

## Request Budget

Shared wall-clock and HTTP request meters for one feed build. Constructed via `RequestSession::RuntimePolicy.resources_for(config)` (policy + budget from one expansion); `budget_for` remains a thin alias. `FeedPipeline` builds sessions with `RequestSession.build` (Context normalizes once — no `RuntimeInput` passthrough). `RequestService::Context` requires an explicit `budget:`. Adapter attempt timeouts resolve through `Budget#effective_timeout_seconds` / `#effective_timeout_ms` — strategies must not reimplement `remaining || policy.total`. Auto fallback run state lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext`.

## HTML-ness

Whether a response document is HTML is owned by `RequestService::Response#html_response?` (Content-Type `text/html`, or a non-JSON body matching `Response::HTML_BODY_SNIFF`). `content_type` stays the wire header. Capture, Channel, and curation inspect all call that one predicate — do not reintroduce a parallel `html_document?`. Gzip/brotli inflate stays on `CompressedBody`, called only from the Faraday adapter; unlabeled octet-stream inflate must not grow onto Botasaurus or LocalFile.

## Botasaurus scrape contract

OpenAPI 2.0 `ScrapeRequest` / `ScrapeSuccess` / `ScrapeError` is the wire authority. CI locks client constants against `spec/fixtures/botasaurus/openapi.yaml` (vendored sibling snapshot); when `../botasaurus-scrape-api/openapi.yaml` is present locally, specs assert the fixture still matches. There is no `ScrapeResponse` alias. Closed sets, wait bounds, request option keys, and `window_size` `{width, height}` live on `RequestService::BotasaurusContract`. `Config::Validator::BotasaurusRequestConfig` consumes those constants for YAML admission (`scroll` is scroll-to-bottom; there is no `scroll_to_bottom`). `BotasaurusStrategy` is Faraday `POST /scrape` plus gem error mapping: 200 → `Success`; 4xx/5xx → `Error` (`challenge_block` → `BlockedSurfaceDetected`, `timeout` / 504 → `RequestTimedOut`, otherwise `BotasaurusServiceError`). **Transport hop** (HTTP to scrape-api, not JSON body): `User-Agent` = `RequestHeaders::DEFAULT_USER_AGENT`, `Accept-Encoding: identity`, per-execute `X-Request-Id`. Target headers stay in `ScrapeRequest.headers`. scrape-api honors inbound `X-Request-Id` for all `diagnostics.request_id` envelopes. `Response#transport_meta` is `diagnostics` plus success-only `metadata_error`. Do not flatten old 1.x field names, parse FastAPI `detail`, or override published OpenAPI defaults.

## DOM chrome

Layout noise and primary-link recognition for the **manual selector** path: ignored container tags/paths, class-clustering exclusions, utility landmarks, heading tags, main-anchor CSS, and visible-text extraction. Owned by `Html2rss::Html::Navigator` (+ `TextExtractor`). `Html::ArticleExtractor` serves selectors only.

Heuristic auto-source chrome lives on `SST::Tags` / `SST::Text` after `SST::Normalizer` (sole Nokogiri on that path).

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking signals. Owned by `Html2rss::Scoring::Engine` (+ `ContainerAssessor`). `LinkResolver` owns token regexp derivation from `PathClassifier::SEGMENT_SETS` (`CONTENT_TOKEN_REGEXP` / `JUNK_TOKEN_REGEXP`); ContainerAssessor consumes those defaults (or injected regexps). Rank-time hard drops live on `Scoring::Observation#hard_junk?` (container assessment — not content-anchor eligibility). `SemanticHtml` / `Html` orchestrate Normalizer → Segmenter → Scoring → `Html::SstArticleExtractor` only. Scrapers supply one page-scoped `Scoring::LinkResolver` into Segmenter, Engine, and SemanticHtml dedup.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned by `Html2rss::LinkDestination::NoisePolicy`. Utility-landmark ancestry is computed by `AutoSource::Segmenter#landmark_ancestor?` and injected as `utility_landmark_ancestor:` — NoisePolicy does not walk `SST::Index`. Primary-link ranking weights are inlined in `Segmenter::PrimaryLink#candidate_facts`. Feature ids and `Score`/`RankedSegment` factories live on `Scoring::Engine`. Segmenter discovers candidates and may _call_ NoisePolicy; it does not own eligibility weights. Scrapers pass the page `LinkResolver` into Segmenter so DestinationFacts memoization stays local to the page run.

## Feed-item admission

Whether an extracted candidate may become a feed item. Owned by `Html2rss::AutoSource::Cleanup` (scheme/domain/self-link/title floor **and** destination-class hard exclude). Destination facts come from `LinkDestination::DestinationFacts` / `PathClassifier` — Cleanup does not own path lexicon Sets. Title string backstop stays `Cleanup.junk_reason` only. Scoring may demote or rank-time drop for heuristic discovery; it does not admit feed items. `AutoSource` short-circuits Html when earlier tiers already admitted ≥1 clean article below `limit` (quality over padding).

## Enhance leftover fields

Visible leftover after excluding heading/anchor/kicker/`time` is split once on block newlines. Keep/drop (CTA, date-shaped, field labels, type chips, title echo, listing section names) is owned only by `Html2rss::Html::ArticleRules::Description`. Dates stay on `ArticleRules::Date` (datetime attrs + date-shaped leftover lines, channel `time_zone`; invalid identifiers fall back to UTC so extract does not raise). Categories stay on `ArticleRules::Category` (class tokens, not layout `label`/`section` substrings) and reject Description keepers except type chips, which are leftover chrome rather than taxonomy. Both `Html::ArticleExtractor` and `Html::SstArticleExtractor` call those modules — do not copy leftover denylists into `Cleanup.junk_reason`.

## Leftover parent-card walk

When a heading-only item or wrapping `<a>` lacks leftover description and date, extractors climb via `Navigator.parent_until_condition` / `SST::Index#parent_until`. Walk policy (`miss?` / `thin_wrapper?` / `crowded?` from heading count + distinct main hrefs) is owned by `Html2rss::Html::CardWalk`. Adapters still traverse. Capture's items-selector lift is a second job: it shares only `Navigator.usable_card_parent?` stop tags and aborts with `contains_other_root?` (listing-root set). Do not fold Capture lift into CardWalk.

## DOM candidate clustering

Anchorless/classless card discovery is owned by `AutoSource::Segmenter` (`:cluster` strategy). Group ranking weights live in `Scoring::ClusterScorer`. Sitemap discovery remains `AutoSource::Scraper::Sitemap` (XML, not heuristic HTML).

## Channel

Feed channel metadata (title, description, ttl, language, author, image, last_build_date) extracted from the response/document with config overrides. Owned by `Html2rss::Channel`. `FeedBuilder::Rss` and `FeedBuilder::JsonFeed` are format adapters that consume Channel + Article — they do not own channel extraction.

## ItemScope post-process config

Per-item extraction scope carries `channel` (url/time_zone). Post-processor `Context` config is derived as `{ channel: scope.channel }` in `ItemScope#context_for` — there is no parallel `post_process_config` bag.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for` (e.g. `rel_next` → `Pager::RelNext`).

## Extractor / post-processor registry

Extractor and post-processor names live in `Selectors::Extractors::NAME_TO_CLASS` and `Selectors::PostProcessors::NAME_TO_CLASS`. `Config::SelectorsValidator::Selector` derives required option fields from each class's `Options` and types from `OPTION_TYPES` / `OPTIONAL_OPTION_TYPES` (when defined); schema enums for `extractor` and `post_process[].name` are overlaid from the same registries. Do not hardcode name lists or per-name `case` type soups in the validator or schema.
