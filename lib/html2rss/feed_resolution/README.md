# FeedResolution

Backend-only entry URL tournament: when the pasted URL is a weak homepage/hub
(or NativeFeed-majority extract), probe same-origin listing/feed candidates and
sticky-rewrite the scrape URL only when the retry extract yields items
(`try_apply!` `:succeeded`) before AutoFallback escalates strategies.

Goal: best **article listing** for AutoSource. A native feed may still win the
tournament on item count (feed-as-means) — intentional.

## Ownership

| Concern                                                                                    | Owner                                                      |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| When to resolve (`articles:` required; floor / weak / NativeFeed ≥50%)                     | `FeedResolution::Policy`                                   |
| Candidate mix (1 feed + up to 4 listing; taxonomy nav; segment first-wins)                 | `FeedResolution::CandidateGenerator`                       |
| Listing path lexicon (`LISTING_PATHS`)                                                     | `Syndication::CandidateCatalog` (consumed, not owned here) |
| Cheap probe + score + winner pick                                                          | `FeedResolution::Probe` + `FeedResolution::Scorer`         |
| Typed entry_resolution options                                                             | `FeedResolution::Options`                                  |
| Wire-safe resolution diag (`applied` = tournament win, not sticky URL)                     | `FeedResolution::Diag`                                     |
| Public `call` → `Result`; retry orchestration (sticky `ScrapeTarget` only on `:succeeded`) | `FeedResolution` (`try_apply!`)                            |
| Page surface for policy/scoring                                                            | `PageRecon::Assessment` + `Html2rss::SurfaceCategory`      |
| Native feed discover/parse                                                                 | `Syndication` (not this module)                            |

### CandidateGenerator mix

- **Feed slot:** first `Syndication::Discovery.candidate_urls` only (alternates precede path guesses).
- **Listing fill** (cap = `max - 1` when `max > 1`; `max == 1` → feed only): nav (`taxonomy_path +3`, `content_path +1`) → segment first-wins (`:list` → `:cluster` → `:semantic`, ≥2 same-origin primary links) → `LISTING_PATHS`.
- Same-page / same-registrable-domain filters; feed never pads into listing slots.

### Policy gates

Resolve when eligible config **and** not blocked **and** any of:

- `articles.size < ARTICLE_FLOOR` (3), or
- surface `weak?`, or
- ≥50% of articles have `scraper == AutoSource::Scraper::NativeFeed` (`native * 2 >= size`; empty → false).

`FeedResolution.call` / `Runner` take **`articles:`** (Array) — not `articles_count:`.

## Non-goals

- Scorer weight overhaul / ranked multi-feed bake-off
- Cross-origin probes
- JSON Feed ingest; Sitemap/WP claim-gates
- Create UI / Site Explorer
- Changing `PageRecon` `:list`-only `discover_segments` (CandidateGenerator owns its own first-wins)
- Syndication parse inside `FeedBuilder`

## Config

`auto_source.entry_resolution: { enabled: true, max_probes: 5 }`
