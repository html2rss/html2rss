# Context — ownership map

Where contributor-facing seams live. Prefer these homes over a second owner.

## Request budget and sessions

| Concern | Home |
| --- | --- |
| Policy + budget for one feed build | `FeedPipeline::RuntimePolicy.resources_for` (`budget_for` is a thin alias) |
| Session construction | `RequestSession.build` (Context normalizes once) |
| Required on every request Context | explicit `budget:` |
| Adapter attempt timeouts | `Budget#effective_timeout_seconds` / `#effective_timeout_ms` |
| Browserless puppet public API | `PuppetCommander#call`; navigation `response_url` on `PuppetCommander::NavigationGuards` |
| Auto fallback run state | `FeedPipeline::AutoFallback::AttemptState` |
| Article collection inputs | `FeedPipeline::ExtractionContext` |

## HTML / AutoSource

| Concern | Home |
| --- | --- |
| DOM chrome constants + visible text | `Html2rss::Html::Navigator` (`IGNORED_CONTAINER_TAGS`, `CLUSTER_EXCLUDED_TAGS`, `UTILITY_LANDMARK_TAGS`, `TextExtractor`) — import, do not redefine |
| Container ranking / `hard_junk?` | `AutoSource::LinkHeuristics#assess_container` → `ContainerSignals` |
| Junk vs content permalink | `AutoSource::LinkHeuristics#noise_anchor?` (Html + SemanticAnchorCandidates consume this) |
| Anchorless / classless list discovery | `AutoSource::Discovery::DomClustering#call` |
| `fallback_anchorless` on SemanticHtml | scraper-local permit flag |
| `fallback_anchorless` on `Html::ArticleExtractor` | field-extraction only — not Discovery |

Heading-linked “Recommended …” titles stay eligible at the noise gate so container `hard_junk?` can keep real posts with publish markers.

## Feed pipeline and rendering

| Concern | Home |
| --- | --- |
| Channel metadata | `Html2rss::Channel.from_response` (or keyword attrs) |
| Format adapters | `FeedBuilder::Rss` / `FeedBuilder::JsonFeed` — consume Channel + Article; constructed by `FeedResult` |
| Opaque scrape handle | `FeedResult`: `empty?`, `channel_title`, `to_rss`, `to_json_feed`, `status` |
| Scrape handoff | `FeedPipeline#to_result` → `FeedResult` (pipeline does not render) |
| Contributor format entrypoints | `Html2rss.feed` / `Html2rss.json_feed` (also `Html2rss.feed_result`) |
| Stylesheets | cached scrape artifact on `FeedResult` |
| `feed_url` | render-time JSON Feed option only |
| Description HTML + RSS non-image enclosure | `FeedBuilder::ItemPresentation` (`description_for`, `rss_enclosure_for`) |
| `Article#description` | raw extracted text only |
| JSON Feed `content_html` / `content_text` | `FeedBuilder::JsonFeed::Item` after presentation returns the body |

Do not expose Channel or Articles readers on `FeedResult`; grow that set only with an explicit consumer-contract change.

Channel projection: Rss uses language/title/description/ttl/link/updated; JsonFeed adds icon/authors.

## Status and dedup

| Concern | Home |
| --- | --- |
| Telemetry on `FeedResult#status` | `Status.build` — version, scraper_tallies, dedup_dropped, auto `selected_strategy`, `attempt_count` (0 outside `:auto`) |
| Generator / user_comment string | `Status#to_generator_comment` (scraper-focused) |
| Observability hash for web | `Status#to_h` (`scraper_status`) — no article bodies/URLs |
| Typed scrape-finished handoff | `FeedPipeline::PipelineOutcome` |
| Dedup before handoff | `#deduplicated_articles` → `[unique, dedup_dropped]` |

## Selectors and pagination

| Concern | Home |
| --- | --- |
| ItemScope channel + post-processor config | `ItemScope#context_for` → `{ channel: scope.channel }` |
| Pagination strategy names / factories | `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names` |
| Runtime pager | `Pager.for` (e.g. `rel_next` → `Pager::RelNext`) |

Selectors validation and the exported JSON schema enum consume `Pager.strategy_names`.
