# Context — deepened request and AutoSource seams

Contributor map for the four Strong module deepenings on this branch. Prefer these homes over reintroducing dual ownership.

## Request Budget

Shared wall-clock and HTTP/interaction meters for one feed build. Constructed only via `RequestSession::RuntimePolicy.budget_for(config)` on every `FeedPipeline` path (fixed strategy and `:auto` fallback). `RequestService::Context` requires an explicit `budget:` — it does not invent a `Budget` when the key is omitted.

## DOM chrome

Layout noise and primary-link recognition for HTML trees: ignored container tags/paths, heading tags, main-anchor CSS, and visible-text extraction. Owned by `HtmlNavigator`. `HtmlExtractor` keeps thin constant/method aliases that delegate for compatibility; discovery and AutoSource scrapers call `HtmlNavigator` directly.

## Container assessment

Observing a semantic container plus its selected anchor and destination facts into ranking/`hard_junk?` signals. Owned by `AutoSource::Scraper::LinkHeuristics#assess_container`, which builds `ContainerSignals`. `SemanticHtml` orchestrates candidates and extraction only — it does not rebuild observation kwargs husks.

## Pagination strategy registry

Supported pagination strategy names and factory classes live in `RequestSession::Pager::STRATEGIES` / `Pager.strategy_names`. Selectors validation (`Selectors::Config::Items`) and the exported JSON schema enum consume that list. Runtime pagination uses `Pager.for`; there is no `RelNextPager` wrapper class.
