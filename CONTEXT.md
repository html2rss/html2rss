# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Request Budget

Shared wall-clock and HTTP/interaction meters for one feed build. Constructed via `RequestSession::RuntimePolicy.resources_for(config)` (policy + budget from one expansion); `budget_for` remains a thin alias. `FeedPipeline` builds sessions with `RequestSession.build` (Context normalizes once — no `RuntimeInput` passthrough). `RequestService::Context` requires an explicit `budget:`. Adapter attempt timeouts resolve through `Budget#effective_timeout_seconds` / `#effective_timeout_ms` — strategies must not reimplement `remaining || policy.total`. `PuppetCommander` public interface is `#call`; navigation `response_url` lives on `PuppetCommander::NavigationGuards`. Auto fallback run state lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext`.

## DOM chrome

Layout noise and primary-link recognition for HTML trees: ignored container tags/paths (`IGNORED_CONTAINER_TAGS`), class-clustering exclusions (`CLUSTER_EXCLUDED_TAGS`), utility landmark tags (`UTILITY_LANDMARK_TAGS`), heading tags, main-anchor CSS, and visible-text extraction (`Html2rss::Html::Navigator::TextExtractor`). Owned solely by `Html2rss::Html::Navigator`. Article field extraction (`Html2rss::Html::Extractor`) and AutoSource discovery/scrapers import those constants — they do not redefine chrome tag sets.

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking/`hard_junk?` signals. Owned by `AutoSource::Scraper::LinkHeuristics#assess_container`, which builds `ContainerSignals` (including `#final_score`). `SemanticHtml` orchestrates candidates and extraction only — it does not rebuild observation kwargs husks or recompute `quality - junk`.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned solely by `AutoSource::Scraper::LinkHeuristics#noise_anchor?` (text/destination rules plus optional icon-only and utility-landmark DOM checks). `Html` and `Discovery::SemanticAnchorCandidates` consume that method; they must not keep parallel `ineligible_anchor?` / `utility_text_suppressed?` policy. Heading-linked “Recommended …” titles are not rejected at this gate so container `hard_junk?` can keep real posts with publish markers.

## Anchorless discovery

Two distinct jobs historically toggled by scraper option `:fallback_anchorless`. Owned by `AutoSource::Scraper::Discovery::Anchorless`:

- `class_cluster_containers` — Html discovers card-like nodes via `ClassClustering` when anchors are weak/absent.
- `permit_unanchored?` — SemanticHtml keeps already-found semantic containers without a primary content anchor.

The config key remains for compatibility; scrapers must call the named APIs. `Html::Extractor`'s `fallback_anchorless:` flag is field-extraction only and is not owned by Discovery.

## Channel

Feed channel metadata (title, description, ttl, language, author, image, last_build_date) extracted from the response/document with config overrides. Owned by `Html2rss::Channel`. `RssBuilder` and `JsonFeedBuilder` are format adapters that consume Channel + Article — they do not own channel extraction.

## ItemScope post-process config

Per-item extraction scope carries `channel` (url/time_zone). Post-processor `Context` config is derived as `{ channel: scope.channel }` in `ItemScope#context_for` — there is no parallel `post_process_config` bag.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for` (e.g. `rel_next` → `Pager::RelNext`).
