# EntryResolution

Backend-only entry URL tournament: when the pasted URL is a weak homepage/hub
(or NativeFeed-majority extract), probe same-origin listing/feed candidates and
sticky-rewrite the scrape URL only when the retry extract yields items
before AutoFallback escalates strategies. `EntryResolution.call` only decides and returns a `Result`;
`AutoFallback` owns the attempt: it records the diagnostic, extracts the winner's already fetched probe
response (no second fetch), and keeps the new URL sticky only when that extract yields items.

Goal: best **article listing** for AutoSource. A native feed may still win the
tournament on item count (feed-as-means) — intentional.

## Ownership

| Concern                                                                                    | Owner                                                      |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| When to resolve (`articles:` required; floor / weak / NativeFeed ≥50%)                     | `EntryResolution::Policy`                                   |
| Candidate mix (1 feed + up to 4 listing; taxonomy nav; segment first-wins)                 | `EntryResolution::CandidateGenerator`                       |
| Listing path lexicon (`LISTING_PATHS`)                                                     | `Syndication::CandidateCatalog` (consumed, not owned here) |
| Cheap probe + score + winner pick                                                          | `EntryResolution::Probe` + `EntryResolution::Scorer`         |
| Typed entry_resolution options                                                             | `EntryResolution::Options`                                  |
| Scope rule (`section` / `site`): which candidates may replace the entry URL                | `EntryResolution::Scope`, applied by `CandidateGenerator`   |
| Wire-safe resolution diag (`applied` = tournament win, not sticky URL)                     | `EntryResolution::Diag`                                     |
| Public `call` → `Result` or `nil` (no tournament); probe cap from the slots it is handed   | `EntryResolution`                                           |
| Attempt lifecycle: slots left for a later strategy, Diag, retry extract, sticky target     | `FeedPipeline::AutoFallback`                               |
| Page surface for policy/scoring                                                            | `AutoSource::Assessment` + `AutoSource::SurfaceCategory`            |
| Native feed discover/parse                                                                 | `Syndication` (not this module)                            |

### CandidateGenerator mix

- **Feed slot:** first same-domain `Syndication::Discovery.candidate_urls` entry. Alternates precede path guesses, except audio-hinted ones on a page without podcast signals. An alternate on another domain is skipped.
- **Listing fill** (cap = `max - 1` when `max > 1`; `max == 1` → feed only): nav (`taxonomy_path +3`, `content_path +1`) → segment first-wins (`:list` → `:cluster` → `:semantic`, ≥2 same-origin primary links) → `LISTING_PATHS`.
- Same-page / same-registrable-domain filters; feed never pads into listing slots.
- **Scope filter (`Scope`):** with `scope: section` (default) a candidate, feed or listing, survives only when its path starts with the entry URL's directory (`/politik/` → `/politik/`, `/news/world` → `/news/world/`, `/inland/index.html` → `/inland/`). A site feed never competes for a section entry; a root entry (`/`) covers the whole site. `scope: site` allows any same-domain candidate.

### Policy gates

Resolve when eligible config **and** not blocked **and** any of:

- `articles.size < ARTICLE_FLOOR` (3), or
- surface `weak?`, or
- ≥50% of articles have `scraper == AutoSource::Scraper::NativeFeed` (`native * 2 >= size`; empty → false).

When no candidate is in scope (or none wins) and out-of-scope candidates were skipped, the entry keeps its own items: `applied: false`, `reason: :no_in_scope_winner`, and the diag carries `out_of_scope_skipped` (count). MCP/batch scrape expose that diag so the agent can retry with `resolution_scope: site`.

`EntryResolution.call` takes **`articles:`** (Array) — not `articles_count:` — and **`slots:`**, the request slots it may spend
(`AutoFallback` passes the budget left minus one when a later strategy exists). Probes = `min(max_probes, slots)`; no slot, no tournament.

## Non-goals

- Scorer weight overhaul / ranked multi-feed bake-off
- Cross-origin probes
- JSON Feed ingest; Sitemap/WP claim-gates
- Create UI / Site Explorer
- Changing the recon `:list`-only segment discovery (CandidateGenerator owns its own first-wins)
- Syndication parse inside `FeedBuilder`

## Config

`auto_source.entry_resolution: { enabled: true, max_probes: 5, scope: section }` (`scope`: `section` | `site`). Shortcut input: `resolution_scope` on `Html2rss.scrape`, CLI `scrape --resolution-scope`, MCP `scrape` / `batch_scrape`, mapped by `Config::AutoSourceRequest`.
