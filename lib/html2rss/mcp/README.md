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
2. **Reusable feed YAML?** → `capture` → `test` → `apply`. `capture` returns YAML in `payload.yaml`. Strive `enhance: true` (false only when chrome leaks). `test` runs schema + live extraction; `apply` is the ship gate (`isError` on zero items).
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
| `html2rss://runtime`    | `botasaurus_configured` boolean (never the scraper URL)    |

## Prompts

| Name                  | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `scrape-webpage`      | One `scrape` call; `inspect` only if weak or recon needed    |
| `capture-feed-config` | Capture YAML → test → apply; catalog rewrite; strive enhance |

## Strategy note

`scrape` / `capture` with `strategy: "auto"` run the full AutoFallback chain. `inspect` maps `auto` to Faraday for cheap diagnostics; pin `botasaurus` when you need browser rendering for inspect.
