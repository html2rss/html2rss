# PageRecon — inspect diagnostics

`PageRecon::Diagnostics` powers the **inspect** verb (CLI, MCP, `Html2rss.inspect`). It fetches once via `PageRecon.probe`, classifies the surface, counts cheap AutoSource articles, and reports redirect facts. Full curation contract: `CONTEXT.md` § Frozen contract.

## What inspect reports

| Field              | Meaning                                                                     |
| ------------------ | --------------------------------------------------------------------------- |
| `requested_url`    | URL you passed in                                                           |
| `final_url`        | URL after redirects (may differ from requested)                             |
| `status`           | HTTP status of the **final** response                                       |
| `scheme_downgrade` | `true` when HTTPS entry landed on HTTP                                      |
| `alternate_feeds`  | `rel=alternate` RSS/Atom links found in HTML                                |
| `surface_category` | AutoSource surface class (`high_entropy_surface`, `unsupported_surface`, …) |
| `articles_count`   | Cheap AutoSource extract (limit 10) — diagnostic only, not ship quality     |
| `strategy`         | Concrete transport used (`inspect` maps `auto` → Faraday)                   |

CLI text output omits `requested_url`; it prints the requested URL as the card title. The `Final:` line appears **only when** `final_url` differs from `requested_url`:

```text
https://apex.example/
        Final:    https://www.example/ (HTTP 200)
        Surface:  high_entropy_surface (10 articles)
```

That `Final:` line means the redirect **did** happen — not that inspect stopped at the apex host.

## Apex → www redirects

Some publishers redirect apex domains to `www` (301). html2rss follows redirects and records the landing URL in `final_url`.

Observed behavior:

```bash
bin/html2rss inspect https://apex.example
# Final: https://www.example/ (HTTP 200), high_entropy_surface, articles

bin/html2rss inspect https://www.example
# high_entropy_surface, articles (no Final: line — requested equals final)
```

Cross-host redirects (e.g. `apex.example` → `www.example`) no longer pin a stale `Host` header from the entry URL. `Config::RequestHeaders` omits `Host` by default; Faraday/Net::HTTP sets it per hop from the current request URL.

### What to do

1. **Prefer the canonical URL** — if you know the site lives on `www`, pass that URL to inspect, recon, capture, and scrape.
2. **Read the `Final:` line** — when `final_url` differs from what you typed and status is 4xx, retry inspect on `final_url` before assuming the site is unreachable.
3. **Do not treat apex 403 as “redirect skipped”** — check JSON output (`--format json`) for `requested_url` vs `final_url` when text output is ambiguous.
4. **Blocked surfaces** — if the canonical URL still fails, try `strategy: botasaurus` on inspect (MCP) or escalate to recon/capture with browser strategy; Faraday-only inspect is intentionally cheap.

## inspect ≠ recon

| Verb    | Adds beyond diagnostics                                              |
| ------- | -------------------------------------------------------------------- |
| inspect | Scraper eligibility, XHR hints (Botasaurus), surface + article count |
| recon   | Verdict (`:build` / `:defer` / `:drop`), native feed preference      |

Follow golden-path `next_step` from MCP envelopes; do not call recon when inspect already answers the question.

## Ownership

| Concern                             | Owner                                                                |
| ----------------------------------- | -------------------------------------------------------------------- |
| Diagnostic fetch + assess           | `PageRecon::Diagnostics` → `PageRecon.probe`                         |
| Surface class + cheap article count | `PageRecon::Assessment`                                              |
| Redirect follow + terminal retry    | `RequestService::FaradayStrategy`                                    |
| Outbound header normalization       | `Config::RequestHeaders` (no default `Host`; explicit override only) |
