# MCP — curation wire surface

MCP exposes the same seven user-facing verbs as the CLI and gem facades. Full contract and ownership: `CONTEXT.md` § Frozen contract. Contributor law: `AGENTS.md` § Curation CLI / MCP.

## Verb table

| Verb     | MCP tool   | Job                                                          |
| -------- | ---------- | ------------------------------------------------------------ |
| inspect  | `inspect`  | `Curation::Inspect` (final URL, status, alternates, surface)         |
| recon    | `recon`    | Verdict + native_feed preference                             |
| capture  | `capture`  | YAML draft config                                            |
| validate | `validate` | Schema only                                                  |
| test     | `test`     | Schema + live extraction                                     |
| apply    | `apply`    | Ship RSS from config (`Curation::Apply::Result`; zero items = isError) |
| scrape   | `scrape`   | Articles now (one-shot)                                      |

Batch: `batch_inspect`, `batch_recon`, `batch_scrape`.

**Golden path:** optional inspect → recon → capture → test → apply. Side door: validate. One-shot: scrape.

## Decision tree

1. **Articles now (no saved config)?** → `scrape` (or `batch_scrape` for multiple URLs). `strategy: "auto"` runs default (HTTPX) → Botasaurus; do not retry with explicit `default` after `auto`.
2. **Reusable feed YAML?** → `capture` → `test` → `apply`. `capture` returns YAML in `payload.yaml`. Strive `enhance: true` (false only when chrome leaks). `test` runs schema + live extraction; optional `compare_enhance` compares enhance off vs on. `apply` is the ship gate (`isError` on zero items). Both `test` and `apply` may include `quality_report.enhance_gains` when `selectors.items.enhance` is true.
3. **Weak scrape/capture or recon?** → `inspect` (or `batch_inspect`). When alternates warrant it, follow `next_step` to `recon`.
4. **Config already in hand?** → `validate` (schema only) → `test` → `apply`.
   - `validate` failures return `payload.issues` (array of `{ path, code, message, expected, actual }`) — not a nested `errors` hash.
   - `test` schema failures surface the same shape under `payload.validation_issues`.

`scrape` and each successful `batch_scrape` row carry `scrape_url` (the page the items were extracted from) and, only when entry resolution swapped the requested URL for a better page or feed (or kept it because every better page lay outside the requested section: `reason: no_in_scope_winner`, `out_of_scope_skipped`), `entry_resolution` (`applied`, `probe_count`, `reason`, `winner_score`). Optional `resolution_scope` (`section` default, `site`) on `scrape` and `batch_scrape` widens how far resolution may leave the requested URL. Compare `scrape_url` to the requested URL.

Prefer `capture` for durable configs; `scrape` / `batch_scrape` for one-shot extraction. Follow envelope `next_step` and `guidance`; do not parse scrape text as a raw item array.

## Envelope

Every tool result is one JSON object (text body and `structuredContent`):

| Field       | Role                                                         |
| ----------- | ------------------------------------------------------------ |
| `ok`        | Success vs schema/ship failure                               |
| `next_step` | Bare verb name or `done` / `read_runtime` / `stop`           |
| `guidance`  | Agent instruction (from `Outcome::Playbook`)                 |
| `payload`   | Tool-specific data (`yaml`, `rss`, `items`, recon fields, …) |
| `cache`     | Optional: `{ hits, max_age_seconds }` when cached pages fed the result |

`Contract.response` builds the wire body; `Outcome` owns `next_step` policy.

Error envelopes (`ok: false`) carry `payload.class`, `payload.message`, `payload.url` (single-URL tools only) and the error's sparse `diagnostics` (`strategy_attempts`, `request_id`, `timeout_phase`, `surface_category`, ...) when present; never `final_url` or `status`. `next_step` is `stop` (do not call `inspect` again) for empty extractions no strategy can read (`unsupported_surface`, `high_entropy_surface`) or where Botasaurus already ran, internal bugs (non-`Html2rss::Error`) rejected caller options (`InvalidOption`) and deterministic rejections (`FeedPipeline::AutoFallback::NON_FALLBACK_ERRORS`); `read_runtime` / `validate` for their config errors; `inspect` for everything else, except that an error never names the tool that just failed (that is `stop`) (timeouts, connection failures, blocked surface, empty extraction, other `Html2rss::Error`).

Missing or schema-breaking tool arguments (any tool) come back as the same error envelope with `next_step: validate`, built by `Server::ArgumentGate` before the SDK's plain-text rejection; the published input schemas are unchanged.

### `next_step` decisions

`Outcome` owns every row; guidance is always `Playbook.guidance(next_step, reason)` (the step's copy plus why it was chosen) and names `payload.<field>` only for fields that outcome carries (`spec/integration/mcp_agent_loop_spec.rb`).

| Result                                                                                | `next_step`    |
| ------------------------------------------------------------------------------------- | -------------- |
| scrape with items                                                                     | `done`         |
| scrape empty, auto/botasaurus run with Botasaurus configured                          | `stop`         |
| scrape empty otherwise                                                                | `inspect`      |
| inspect with alternates                                                               | `recon`        |
| inspect with articles                                                                 | `capture`      |
| inspect, response not HTML (PDF, image) or surface unreadable                         | `stop`         |
| inspect, JS shell or blocked page, Botasaurus not yet run and configured              | `scrape`       |
| inspect, JS shell or blocked page, Botasaurus unset                                   | `read_runtime` |
| inspect, JS shell or blocked page, Botasaurus already ran                             | `stop`         |
| inspect, static empty page                                                            | `capture`      |
| capture with native feed                                                              | `done`         |
| capture with articles and selectors                                                   | `test`         |
| capture with articles, no selectors                                                   | `scrape`       |
| capture with no articles                                                              | `stop`         |
| test success / schema failure / any other failure                                     | `apply` / `validate` / `stop` |
| apply with rendered items / none                                                      | `done` / `stop` |

Batch rows: a row whose URL raised (any batch verb) carries the single-URL error fields (`class`, `message`, sparse diagnostics) and `next_step`, built by `Outcome.from_error` as if a single call to that verb had raised; other `batch_inspect` and `batch_recon` rows carry the `next_step` a single call would give. The top level stays `done` when any URL succeeded (guidance counts the failures), and keeps the verb's own step when none did.

## Ownership

| Concern                                       | Owner                                            |
| --------------------------------------------- | ------------------------------------------------ |
| Tool schemas, titles, strategy enum           | `MCP::Contract`                                  |
| Catalog fingerprint + `mcp_contract_version` | `MCP::Contract` (+ `Runtime.snapshot` wire)      |
| Envelope factories, `next_step` routing       | `MCP::Outcome`                                   |
| Runtime instructions, guidance, prompt bodies | `Outcome::Playbook` (SSOT — `Server` delegates)  |
| Diagnostic fetch + assess                     | `Inspect`                         |
| Curation verdict                              | `Recon`                                          |
| Capture YAML product                          | `Curation::Capture::CaptureResult#yaml`                    |
| Batch concurrency                             | `Curation::Batch.map` (Thread pool; preserves input order) |

Do not duplicate playbook prose in `server.rb`.

## Resources

| URI                     | Description                                                |
| ----------------------- | ---------------------------------------------------------- |
| `html2rss://schema`     | Full JSON Schema for feed configurations                   |
| `html2rss://extractors` | Registered extractor names                                 |
| `html2rss://strategies` | Published MCP strategies (`auto`, `default`, `httpx`, `botasaurus`) |
| `html2rss://runtime`    | `version`, `mcp_contract_version`, `catalog_fingerprint`, `tools`, `botasaurus_configured`, `response_cache_ttl` (never the scraper URL). Fingerprint covers tool names, required keys, and `oneOf` branches; bump `mcp_contract_version` for envelope semantics. |

## Prompts

| Name                  | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `scrape-webpage`      | One `scrape` call; `inspect` only if weak or recon needed    |
| `capture-feed-config` | Capture YAML → test → apply; catalog rewrite; strive enhance |

## Response cache

The MCP process is long-lived, so an agent iterating `inspect → capture → validate → test` on one URL should not refetch it. `RequestService::ResponseCache` is installed at server start, **on by default with a 300s TTL**. Set `HTML2RSS_RESPONSE_CACHE_TTL=<seconds>` to change it, or `0` / `off` / `false` to disable; an unusable value logs a warning and uses the default.

- Only initial 2xx fetches are cached, keyed by a digest of URL, strategy, headers, request options, and policy limits. Follow-ups and block pages always hit the network.
- Memory is bounded: at most 32 entries and 32 MiB of bodies, oldest evicted first.
- When a result was built from cached pages, the envelope carries `cache: { hits, max_age_seconds }`; absent means everything was fetched live. Wait out the TTL or restart with the cache off to force a refetch.
- `html2rss://runtime` publishes `response_cache_ttl` (`null` when off).

The one-shot CLI has no use for it; use `capture` or `--input -` for offline iteration.

## Strategy note

`scrape` / `capture` with `strategy: "auto"` run the full AutoFallback chain. `inspect` maps `auto` to default (HTTPX) for cheap diagnostics; pin `botasaurus` when you need browser rendering for inspect.

## Inspect redirects

`payload.final_url` is the post-redirect landing URL. When it differs from the URL you passed and `status` is 4xx, inspect still followed redirects — retry on `final_url` or pass the site's canonical hostname (often `www`). Cross-host redirects set `Host` per hop; html2rss does not pin the entry hostname. See [`page_probe/README.md`](../page_probe/README.md).
