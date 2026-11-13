# Syndication

Native RSS/Atom/RDF discovery and parse for auto-source promotion and direct feed URLs.

## Ownership

| Concern                                                          | Owner                                                                                              |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Head `rel=alternate` (audio-hinted first on a podcast page, after the path guesses elsewhere) + common path probes + status-gated feedish | `Syndication::Discovery`                                      |
| Native feed of a fetched page for Recon, Capture and Test        | `Syndication::Discovery.native_feed_url` (one entry point: the page response they already hold, at the URL a redirect landed on) |
| Cross-origin permission for a page's advertised feed             | `RequestService::Policy` (proof: `RequestService::FeedAdvertisement`)                              |
| RSS 2.0 / RSS 1.0 (RDF) / Atom → `Syndication::Feed` (article hashes + channel facts); item URL: an http(s) link, else an http(s) guid, else the first audio/video file | `Syndication::Parser` |
| Item media files and image (enclosure, Media RSS, iTunes) → item | `Syndication::ItemMedia` (called by `Parser`; http(s) only via `Url.resolve_web`; sizes, durations and player pages via `Article::Enclosure`) |
| Channel facts (author, `itunes:category`, `itunes:explicit`) → `Feed#channel` | `Syndication::ChannelFacts` (called by `Parser` on the same parse; precedence over page meta is `Channel`'s) |
| Strict head-only link parse (no path guessing)                   | `Html::FeedLink`                                                                                   |
| Response Content-Type / body feed sniff                          | `RequestService::Response#feed_response?` (sole sniff owner; Discovery only adds HTTP status gate) |

## Non-goals

- Entry-URL tournament / listing resolution (`FeedResolution`)
- Page recon / surface classification (`PageRecon`)
- Feed channel metadata for output and its precedence (`Channel` / `FeedBuilder`); Syndication only reads what a feed states
- Ranking or quality scoring of competing feeds beyond the audio-hint order and first feedish hit

Discovery stops at the first feedish URL (lazy probe). Head alternates are fetched as `:advertised_feed` with the page's `FeedAdvertisement`, so a feed on another host (a podcast platform) is followed. An advertised `http:` feed off the page origin is fetched as `https:` or skipped. Path guesses stay same-origin. Alternates keep document order, except on a podcast page: `podcast`, `episode` or `audio` (word-ish, plural allowed) in its URL host, path or `<title>`, an `og:type` of `music.*` or `video.*`, or a JSON-LD `@type` `PodcastSeries`, `PodcastEpisode` or `AudioObject` anywhere (regex on the script text, no JSON parse). There, an alternate whose title or URL hints audio (the same words plus `mp3`, `m4a`, `aac`, `opus`) goes first. On any other page those rank after the same-origin path guesses, and other alternates still precede them. A news front page that advertises only its podcast ships its page items or a same-origin feed, not the episodes; the podcast feed is its last candidate.

An item without a link takes its guid (Atom `id`, RDF `rdf:about`) when that is an absolute http(s) URL, whatever `isPermaLink` says, else its first audio or video file. Relative, `urn:` and `tag:` ids name no page. An item with none of these is skipped. Links, files and images resolve against the feed URL through `Url.resolve_web`, so a `javascript:`, `data:` or `ftp:` one counts as absent. A followed feed's items may link to the feed's own domain as well as the page's (AutoSource `Cleanup`, which owns that rule). Path guessing mirrors the legacy configs `probe_rss` script; that script should eventually thin-wrap this module.
