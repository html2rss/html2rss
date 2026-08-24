# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Scrape target

Immutable entry vs effective fetch URL for one pipeline run. Owned by `Html2rss::ScrapeTarget` — constructed from `Config#url`, updated when `FeedResolution.try_apply!` selects a winner (including zero-item retries so later auto-fallback strategies keep the resolved URL). `RequestSession.build` accepts an optional `scrape_url:` override; do not mutate `Config` for resolution rewrites.

## Page assessment

Cheap surface class and admitted article count for policy gates and probe scoring. Owned by `PageRecon::Assessment` via `PageRecon.assess` (fixed AutoSource limit). Full pipeline extract counts stay on `FeedPipeline#deduplicated_articles`; do not reintroduce parallel `classify_no_scraper_surface` call sites for resolution gates.

## Syndication candidate catalog

Shared path lexicon for native feed discovery and entry-resolution listing guesses. Owned by `Syndication::CandidateCatalog` (`FEED_PATHS`, `LISTING_PATHS`). `Syndication::Discovery` and `FeedResolution::CandidateGenerator` consume it — do not duplicate path arrays.

## Feed resolution scoring

Probe score weights and drop penalties for the entry URL tournament. Owned by `FeedResolution::Scorer`. `FeedResolution::Probe` fetches; `Selector` picks winners from `Probe::Scored` — do not inline scoring in `Probe`.

## Request Budget

Shared wall-clock and HTTP request meters for one feed build. Constructed via `RequestSession::RuntimePolicy.resources_for(config)` (policy + budget from one expansion); `budget_for` remains a thin alias. `FeedPipeline` builds sessions with `RequestSession.build` (Context normalizes once — no `RuntimeInput` passthrough). `RequestService::Context` requires an explicit `budget:`. Adapter attempt timeouts resolve through `Budget#effective_timeout_seconds` / `#effective_timeout_ms` — strategies must not reimplement `remaining || policy.total`. Auto fallback run state lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext`.

## HTML-ness

Whether a response document is HTML is owned by `RequestService::Response#html_response?` (Content-Type `text/html`, or a non-JSON body matching `Response::HTML_BODY_SNIFF`). `content_type` stays the wire header. Capture, Channel, and MCP Inspect all call that one predicate — do not reintroduce a parallel `html_document?`. Gzip/brotli inflate stays on `CompressedBody`, called only from the Faraday adapter; unlabeled octet-stream inflate must not grow onto Botasaurus or LocalFile.

## Botasaurus scrape contract

OpenAPI 2.0 `ScrapeRequest` / `ScrapeSuccess` / `ScrapeError` is the wire authority. CI locks client constants against `spec/fixtures/botasaurus/openapi.yaml` (vendored sibling snapshot); when `../botasaurus-scrape-api/openapi.yaml` is present locally, specs assert the fixture still matches. There is no `ScrapeResponse` alias. Closed sets, wait bounds, request option keys, and `window_size` `{width, height}` live on `RequestService::BotasaurusContract`. `Config::Validator::BotasaurusRequestConfig` consumes those constants for YAML admission (`scroll` is scroll-to-bottom; there is no `scroll_to_bottom`). `BotasaurusStrategy` is Faraday `POST /scrape` plus gem error mapping: 200 → `Success`; 4xx/5xx → `Error` (`challenge_block` → `BlockedSurfaceDetected`, `timeout` / 504 → `RequestTimedOut`, otherwise `BotasaurusServiceError`). **Transport hop** (HTTP to scrape-api, not JSON body): `User-Agent` = `RequestHeaders::DEFAULT_USER_AGENT`, `Accept-Encoding: identity`, per-execute `X-Request-Id`. Target headers stay in `ScrapeRequest.headers`. scrape-api honors inbound `X-Request-Id` for all `diagnostics.request_id` envelopes. `Response#transport_meta` is `diagnostics` plus success-only `metadata_error`. Do not flatten old 1.x field names, parse FastAPI `detail`, or override published OpenAPI defaults.

## DOM chrome

Layout noise and primary-link recognition for the **manual selector** path: ignored container tags/paths, class-clustering exclusions, utility landmarks, heading tags, main-anchor CSS, and visible-text extraction. Owned by `Html2rss::Html::Navigator` (+ `TextExtractor`). `Html::ArticleExtractor` serves selectors only.

Heuristic auto-source chrome lives on `SST::Tags` / `SST::Text` after `SST::Normalizer` (sole Nokogiri on that path).

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking signals. Owned by `Html2rss::Scoring::Engine` (+ `ContainerAssessor`). `LinkResolver` owns token regexp derivation from `PathClassifier::SEGMENT_SETS` (`CONTENT_TOKEN_REGEXP` / `JUNK_TOKEN_REGEXP`); ContainerAssessor consumes those defaults (or injected regexps). Rank-time hard drops live on `Scoring::Observation#hard_junk?` (container assessment — not content-anchor eligibility). `SemanticHtml` / `Html` orchestrate Normalizer → Segmenter → Scoring → `Html::SstArticleExtractor` only. Scrapers supply one page-scoped `Scoring::LinkResolver` into Segmenter, Engine, and SemanticHtml dedup.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned by `Html2rss::LinkDestination::NoisePolicy`. Utility-landmark ancestry is computed by `AutoSource::Segmenter#landmark_ancestor?` and injected as `utility_landmark_ancestor:` — NoisePolicy does not walk `SST::Index`. Primary-link ranking weights are inlined in `Segmenter::PrimaryLink#candidate_facts`. Feature ids and `Score`/`RankedSegment` factories live on `Scoring::Engine`. Segmenter discovers candidates and may *call* NoisePolicy; it does not own eligibility weights. Scrapers pass the page `LinkResolver` into Segmenter so DestinationFacts memoization stays local to the page run.

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
