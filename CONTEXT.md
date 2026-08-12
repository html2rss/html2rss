# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Request Budget

Shared wall-clock and HTTP/interaction meters for one feed build. Constructed via `RequestSession::RuntimePolicy.resources_for(config)` (policy + budget from one expansion); `budget_for` remains a thin alias. `FeedPipeline` builds sessions with `RequestSession.build` (Context normalizes once — no `RuntimeInput` passthrough). `RequestService::Context` requires an explicit `budget:`. Adapter attempt timeouts resolve through `Budget#effective_timeout_seconds` / `#effective_timeout_ms` — strategies must not reimplement `remaining || policy.total`. `PuppetCommander` public interface is `#call`; navigation `response_url` lives on `PuppetCommander::NavigationGuards`. Auto fallback run state lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext`.

## DOM chrome

Layout noise and primary-link recognition for HTML trees: ignored container tags/paths (`IGNORED_CONTAINER_TAGS`), class-clustering exclusions (`CLUSTER_EXCLUDED_TAGS`), utility landmark tags (`UTILITY_LANDMARK_TAGS`), heading tags, main-anchor CSS, and visible-text extraction (`Html2rss::Html::Navigator::TextExtractor`). Owned solely by `Html2rss::Html::Navigator`. Article field extraction (`Html2rss::Html::ArticleExtractor`) and AutoSource discovery/scrapers import those constants — they do not redefine chrome tag sets.

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking/`hard_junk?` signals. Owned by `AutoSource::LinkHeuristics#assess_container`, which builds `ContainerSignals` (including `#final_score`). `SemanticHtml` orchestrates candidates and extraction only — it does not rebuild observation kwargs husks or recompute `quality - junk`.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned solely by `AutoSource::LinkHeuristics#noise_anchor?` (text/destination rules plus optional icon-only and utility-landmark DOM checks). `Html` and `Discovery::SemanticAnchorCandidates` consume that method; they must not keep parallel `ineligible_anchor?` / `utility_text_suppressed?` policy. Heading-linked “Recommended …” titles are not rejected at this gate so container `hard_junk?` can keep real posts with publish markers.

## DOM candidate clustering

Candidate list discovery for anchorless or classless pages is owned by `AutoSource::Discovery::DomClustering`. It encapsulates class clustering with lazy fallback to 1-level tag structure clustering behind a single `#call` interface with shared scoring and overlap resolution. `SemanticHtml` uses its own `:fallback_anchorless` boolean directly. `Html::ArticleExtractor`'s `fallback_anchorless:` flag is field-extraction only and is not owned by Discovery.

## Channel

Feed channel metadata (title, description, ttl, language, author, image, last_build_date) materialized via `Html2rss::Channel.from_response` (or keyword attrs). Owned by `Html2rss::Channel`. `FeedBuilder::Rss` and `FeedBuilder::JsonFeed` are format adapters that consume Channel + Article — they do not own channel extraction. `FeedResult` constructs those adapters directly (no `FeedBuilder.build` dispatcher). Stylesheets are a cached scrape artifact on FeedResult; `feed_url` is a render-time JSON Feed-only option. Channel projection: Rss uses language/title/description/ttl/link/updated; JsonFeed adds icon/authors.

## FeedResult

Closed Marshal-cacheable handle for one scrape. Frozen public query/render set: `empty?`, `channel_title`, `to_rss`, `to_json_feed`, `status`. Non-goals: do **not** expose Channel or Articles readers; do not grow this set without an explicit consumer-contract change. Materialization owns Channel + Status + articles internally; format adapters render from that private payload. `status.to_h` remains the observability payload for web (`scraper_status`).

## Status

Consumer-facing scrape telemetry on `FeedResult#status`: version, scraper_tallies, dedup_dropped, plus auto-path `selected_strategy` (Symbol or nil) and `attempt_count` (Integer; 0 outside `:auto`). Built via `Status.build`. `to_generator_comment` stays scraper-focused (no strategy bloat). `to_h` keys are additive for web. Must not include article bodies/URLs. Owned by `Html2rss::Status`; scrape-finished handoff arrives via `FeedPipeline::PipelineOutcome`.

## ItemScope post-process config

Per-item extraction scope carries `channel` (url/time_zone). Post-processor `Context` config is derived as `{ channel: scope.channel }` in `ItemScope#context_for` — there is no parallel `post_process_config` bag.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for` (e.g. `rel_next` → `Pager::RelNext`).
