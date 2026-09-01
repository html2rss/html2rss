# MCP — curation wire surface

MCP exposes the same seven user-facing verbs as the CLI and gem facades. Full contract and ownership: `CONTEXT.md` § Frozen contract. Contributor law: `AGENTS.md` § Curation CLI / MCP.

## Verb table

| Verb | MCP tool | Job |
| --- | --- | --- |
| inspect | `inspect` | Diagnostics (final URL, status, alternates, surface) |
| recon | `recon` | Verdict + native_feed preference |
| capture | `capture` | YAML draft config |
| validate | `validate` | Schema only |
| test | `test` | Schema + live extraction |
| apply | `apply` | Ship RSS from config |
| scrape | `scrape` | Articles now (one-shot) |

Batch: `batch_inspect`, `batch_recon`, `batch_scrape`.

**Golden path:** optional inspect → recon → capture → test → apply. Side door: validate. One-shot: scrape.

## Decision tree

**`Outcome::Playbook` owns runtime instructions, guidance, and prompt bodies** — `MCP::Server` delegates; do not duplicate prose in `server.rb`. *(Wave 2A)*

Wire schemas and tool titles live in `MCP::Contract`. Envelope factories and `next_step` policy live in `MCP::Outcome`.
