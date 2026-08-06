# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Request Budget

Shared wall-clock and HTTP/interaction meters for one feed build. Constructed only via `RequestSession::RuntimePolicy.budget_for(config)` on every `FeedPipeline` path (fixed strategy and `:auto` fallback). `RequestService::Context` requires an explicit `budget:` — it does not invent a `Budget` when the key is omitted. Auto fallback run state (`attempts` + selected result) lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext` (`config` / `response` / `request_session`) instead of repeating that clump.

## DOM chrome

Layout noise and primary-link recognition for HTML trees: ignored container tags/paths (`IGNORED_CONTAINER_TAGS`), class-clustering exclusions (`CLUSTER_EXCLUDED_TAGS`), utility landmark tags (`UTILITY_LANDMARK_TAGS`), heading tags, main-anchor CSS, and visible-text extraction (`Html2rss::Html::Navigator::TextExtractor`). Owned solely by `Html2rss::Html::Navigator`. Article field extraction (`Html2rss::Html::Extractor`) and AutoSource discovery/scrapers import those constants — they do not redefine chrome tag sets.

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking/`hard_junk?` signals. Owned by `AutoSource::Scraper::LinkHeuristics#assess_container`, which builds `ContainerSignals` (including `#final_score`). `SemanticHtml` orchestrates candidates and extraction only — it does not rebuild observation kwargs husks or recompute `quality - junk`.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned solely by `AutoSource::Scraper::LinkHeuristics#noise_anchor?` (text/destination rules plus optional icon-only and utility-landmark DOM checks). `Html` and `Discovery::SemanticAnchorCandidates` consume that method; they must not keep parallel `ineligible_anchor?` / `utility_text_suppressed?` policy. Heading-linked “Recommended …” titles are not rejected at this gate so container `hard_junk?` can keep real posts with publish markers.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for` (e.g. `rel_next` → `Pager::RelNext`).
