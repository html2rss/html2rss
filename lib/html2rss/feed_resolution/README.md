# FeedResolution

Backend-only entry URL tournament: when the pasted URL is a weak homepage/hub,
probe a few same-origin listing/feed candidates and rewrite the scrape URL before
AutoFallback escalates strategies.

## Ownership

| Concern | Owner |
| --- | --- |
| When to resolve | `FeedResolution::Policy` |
| Candidate URLs (cap 5) | `FeedResolution::CandidateGenerator` |
| Cheap probe + score | `FeedResolution::Probe` |
| Winner pick | `FeedResolution::Selector` |
| Public `call` → `Result` | `FeedResolution` |
| Page surface / cheap article count | `PageRecon` (shared) |
| Native feed discover/parse | `Syndication` (not this module) |

## Non-goals

- Create UI / Site Explorer
- Candidate generation inside `Segmenter`
- Syndication parse inside `FeedBuilder`
- Cross-origin probes
- Quality ranking overhaul beyond probe scores

## Config

`auto_source.entry_resolution: { enabled: true, max_probes: 5 }`
