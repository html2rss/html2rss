# MCP — curation wire surface

MCP exposes the same seven user-facing verbs as the CLI and gem facades. Full contract and ownership: `CONTEXT.md` § Frozen contract. Contributor law: `AGENTS.md` § Curation CLI / MCP.

## Verb table

| Verb     | MCP tool   | Job                                                  |
| -------- | ---------- | ---------------------------------------------------- |
| inspect  | `inspect`  | Diagnostics (final URL, status, alternates, surface) |
| recon    | `recon`    | Verdict + native_feed preference                     |
| capture  | `capture`  | YAML draft config                                    |
| validate | `validate` | Schema only                                          |
| test     | `test`     | Schema + live extraction                             |
| apply    | `apply`    | Ship RSS from config                                 |
| scrape   | `scrape`   | Articles now (one-shot)                              |

Batch: `batch_inspect`, `batch_recon`, `batch_scrape`.

**Golden path:** optional inspect → recon → capture → test → apply. Side door: validate. One-shot: scrape.

## Decision tree

1. **Articles now (no saved config)?** → `scrape` (or `batch_scrape` for multiple URLs). `strategy: "auto"` runs Faraday → Botasaurus; do not retry with explicit `faraday` after `auto`.
2. **Reusable feed YAML?** → `capture` → `test` → `apply`. `capture` returns YAML in `payload.yaml`. Strive `enhance: true` (false only when chrome leaks). `test` runs schema + live extraction; optional `compare_enhance` compares enhance off vs on. `apply` is the ship gate (`isError` on zero items). Both `test` and `apply` may include `quality_report.enhance_gains` when `selectors.items.enhance` is true.
3. **Weak scrape/capture or recon?** → `inspect` (or `batch_inspect`). When alternates warrant it, follow `next_step` to `recon`.
4. **Config already in hand?** → `validate` (schema only) → `test` → `apply`.

Prefer `capture` for durable configs; `scrape` / `batch_scrape` for one-shot extraction. Follow envelope `next_step` and `guidance`; do not parse scrape text as a raw item array.

## Envelope

Every tool result is one JSON object (text body and `structuredContent`):

| Field       | Role                                                         |
| ----------- | ------------------------------------------------------------ |
| `ok`        | Success vs schema/ship failure                               |
| `next_step` | Bare verb name or `done` / `read_runtime`                    |
| `guidance`  | Agent instruction (from `Outcome::Playbook`)                 |
| `payload`   | Tool-specific data (`yaml`, `rss`, `items`, recon fields, …) |

`Contract.response` builds the wire body; `Outcome` owns `next_step` policy.

## Ownership

| Concern                                       | Owner                                            |
| --------------------------------------------- | ------------------------------------------------ |
| Tool schemas, titles, strategy enum           | `MCP::Contract`                                  |
| Catalog fingerprint + `mcp_contract_version` | `MCP::Contract` (+ `Runtime.snapshot` wire)      |
| Envelope factories, `next_step` routing       | `MCP::Outcome`                                   |
| Runtime instructions, guidance, prompt bodies | `Outcome::Playbook` (SSOT — `Server` delegates)  |
| Diagnostic fetch + assess                     | `PageRecon::Diagnostics`                         |
| Curation verdict                              | `Recon`                                          |
| Capture YAML product                          | `Capture::CaptureResult#yaml`                    |
| Batch concurrency                             | `Batch.map` (Thread pool; preserves input order) |

Do not duplicate playbook prose in `server.rb`.

## Resources

| URI                     | Description                                                |
| ----------------------- | ---------------------------------------------------------- |
| `html2rss://schema`     | Full JSON Schema for feed configurations                   |
| `html2rss://extractors` | Registered extractor names                                 |
| `html2rss://strategies` | Published MCP strategies (`auto`, `faraday`, `botasaurus`) |
| `html2rss://runtime`    | `version`, `mcp_contract_version`, `catalog_fingerprint`, `tools`, `botasaurus_configured` (never the scraper URL). Fingerprint covers tool names, required keys, and `oneOf` branches; bump `mcp_contract_version` for envelope semantics. |

## Prompts

| Name                  | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `scrape-webpage`      | One `scrape` call; `inspect` only if weak or recon needed    |
| `capture-feed-config` | Capture YAML → test → apply; catalog rewrite; strive enhance |

## Strategy note

`scrape` / `capture` with `strategy: "auto"` run the full AutoFallback chain. `inspect` maps `auto` to Faraday for cheap diagnostics; pin `botasaurus` when you need browser rendering for inspect.

## Inspect redirects

`payload.final_url` is the post-redirect landing URL. When it differs from the URL you passed and `status` is 4xx, inspect still followed redirects — retry on `final_url` or pass the site's canonical hostname (often `www`). Cross-host redirects set `Host` per hop; html2rss does not pin the entry hostname. See [`page_recon/README.md`](../page_recon/README.md).
