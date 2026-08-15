# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Request Budget

Shared wall-clock and HTTP request meters for one feed build. Constructed via `RequestSession::RuntimePolicy.resources_for(config)` (policy + budget from one expansion); `budget_for` remains a thin alias. `FeedPipeline` builds sessions with `RequestSession.build` (Context normalizes once — no `RuntimeInput` passthrough). `RequestService::Context` requires an explicit `budget:`. Adapter attempt timeouts resolve through `Budget#effective_timeout_seconds` / `#effective_timeout_ms` — strategies must not reimplement `remaining || policy.total`. Auto fallback run state lives on `FeedPipeline::AutoFallback::AttemptState`. Article collection threads `FeedPipeline::ExtractionContext`.

## DOM chrome

Layout noise and primary-link recognition for the **manual selector** path: ignored container tags/paths, class-clustering exclusions, utility landmarks, heading tags, main-anchor CSS, and visible-text extraction. Owned by `Html2rss::Html::Navigator` (+ `TextExtractor`). `Html::ArticleExtractor` serves selectors only.

Heuristic auto-source chrome lives on `SST::Tags` / `SST::Text` after `SST::Normalizer` (sole Nokogiri on that path).

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking signals. Owned by `Html2rss::Scoring::Engine` (+ `ContainerAssessor`). Rank-time hard drops live on `Scoring::Observation#hard_junk?` (container assessment — not content-anchor eligibility). `SemanticHtml` / `Html` orchestrate Normalizer → Segmenter → Scoring → `Html::SstArticleExtractor` only. Scrapers supply one page-scoped `Scoring::LinkResolver` into Segmenter, Engine, and SemanticHtml dedup.

## Content-anchor eligibility

Whether an anchor is junk chrome vs a content permalink. Owned by `Html2rss::LinkDestination::NoisePolicy`. Utility-landmark ancestry is computed by `AutoSource::Segmenter#landmark_ancestor?` and injected as `utility_landmark_ancestor:` — NoisePolicy does not walk `SST::Index`. Primary-link ranking weights are inlined in `Segmenter::PrimaryLink#candidate_facts`. Feature ids and `Score`/`RankedSegment` factories live on `Scoring::Engine`. Segmenter discovers candidates and may *call* NoisePolicy; it does not own eligibility weights. Scrapers pass the page `LinkResolver` into Segmenter so DestinationFacts memoization stays local to the page run.

## DOM candidate clustering

Anchorless/classless card discovery is owned by `AutoSource::Segmenter` (`:cluster` strategy). Group ranking weights live in `Scoring::ClusterScorer`. Sitemap discovery remains `AutoSource::Scraper::Sitemap` (XML, not heuristic HTML).

## Channel

Feed channel metadata (title, description, ttl, language, author, image, last_build_date) extracted from the response/document with config overrides. Owned by `Html2rss::Channel`. `FeedBuilder::Rss` and `FeedBuilder::JsonFeed` are format adapters that consume Channel + Article — they do not own channel extraction.

## ItemScope post-process config

Per-item extraction scope carries `channel` (url/time_zone). Post-processor `Context` config is derived as `{ channel: scope.channel }` in `ItemScope#context_for` — there is no parallel `post_process_config` bag.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for` (e.g. `rel_next` → `Pager::RelNext`).
