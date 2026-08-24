# Syndication

Native RSS/Atom discovery and parse for auto-source promotion and direct feed URLs.

## Ownership

| Concern | Owner |
| --- | --- |
| Head `rel=alternate` + common path probes + feedish validation | `Syndication::Discovery` |
| RSS 2.0 / Atom → article hashes | `Syndication::Parser` |
| Strict head-only link parse (no path guessing) | `Html::FeedLink` |
| Response Content-Type / body feed sniff | `RequestService::Response#feed_response?` |

## Non-goals

- Entry-URL tournament / listing resolution (`FeedResolution`)
- Page recon / surface classification (`PageRecon`)
- Feed channel metadata for output (`Channel` / `FeedBuilder`)
- Ranking or quality scoring of competing feeds beyond first feedish hit

Discovery stops at the first same-origin feedish URL (lazy probe). Path guessing mirrors the legacy configs `probe_rss` script; that script should eventually thin-wrap this module.
