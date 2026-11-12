# Syndication

Native RSS/Atom/RDF discovery and parse for auto-source promotion and direct feed URLs.

## Ownership

| Concern                                                          | Owner                                                                                              |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Head `rel=alternate` (audio-hinted first) + common path probes + status-gated feedish | `Syndication::Discovery`                                                      |
| Cross-origin permission for a page's advertised feed             | `RequestService::Policy` (proof: `RequestService::FeedAdvertisement`)                              |
| RSS 2.0 / RSS 1.0 (RDF) / Atom → article hashes                  | `Syndication::Parser`                                                                              |
| Item media files and image (enclosure, Media RSS, iTunes) → item | `Syndication::ItemMedia` (called by `Parser`; sizes, durations and player pages via `Article::Enclosure`) |
| Strict head-only link parse (no path guessing)                   | `Html::FeedLink`                                                                                   |
| Response Content-Type / body feed sniff                          | `RequestService::Response#feed_response?` (sole sniff owner; Discovery only adds HTTP status gate) |

## Non-goals

- Entry-URL tournament / listing resolution (`FeedResolution`)
- Page recon / surface classification (`PageRecon`)
- Feed channel metadata for output (`Channel` / `FeedBuilder`)
- Ranking or quality scoring of competing feeds beyond the audio-hint order and first feedish hit

Discovery stops at the first feedish URL (lazy probe). Head alternates are fetched as `:advertised_feed` with the page's `FeedAdvertisement`, so a feed the page advertises on another host (a podcast platform's feed host) is followed; an advertised `http:` feed off the page origin is fetched as `https:` or skipped. Path guesses stay same-origin. Among several alternates, one whose title or URL hints audio (`podcast`, `audio`, `mp3`, `m4a`, `aac`, `opus`, `episodes`) goes first, else document order. Path guessing mirrors the legacy configs `probe_rss` script; that script should eventually thin-wrap this module.
