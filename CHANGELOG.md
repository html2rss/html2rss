# Changelog

## Unreleased

### Breaking

Curation CLI, MCP, gem facades, and agent playbook unify on seven user-facing verbs. See `CONTEXT.md` § Frozen contract and `AGENTS.md` § Curation CLI / MCP.

**MCP tool renames** (no deprecation shims):

| Before                        | After                           |
| ----------------------------- | ------------------------------- |
| `inspect_url`                 | `inspect`                       |
| _(recon folded into inspect)_ | `recon` _(new standalone tool)_ |
| `capture_config`              | `capture`                       |
| `validate_config`             | `validate`                      |
| `test_config`                 | `test`                          |
| `apply_config`                | `apply`                         |
| `scrape_url`                  | `scrape`                        |
| `batch_inspect_urls`          | `batch_inspect`                 |
| `batch_scrape_urls`           | `batch_scrape`                  |
| —                             | `batch_recon` _(new)_           |

**MCP `next_step` values** rename to match bare verbs (`inspect`, `recon`, `capture`, `validate`, `test`, `apply`, `scrape`, `done`, `read_runtime`).

**MCP `html2rss://runtime` resource** now publishes `version`, `mcp_contract_version`, `catalog_fingerprint`, `tools`, and `botasaurus_configured` (was `botasaurus_configured` only). Bump `mcp_contract_version` when tool names or required inputs change; clients should refresh `tools/list` when `catalog_fingerprint` differs from cache.

**CLI command renames:**

| Before          | After             |
| --------------- | ----------------- |
| `feed`          | `apply`           |
| `auto`          | `scrape`          |
| —               | `inspect` _(new)_ |
| `recon --quiet` | removed           |

**Gem facade / batch API:**

| Before                          | After                                                                                 |
| ------------------------------- | ------------------------------------------------------------------------------------- |
| _(no public inspect facade)_    | `Html2rss.inspect`                                                                    |
| `Html2rss.feed` / `feed_result` | **unchanged internally**; user-facing **`Html2rss.apply`** delegates to `feed_result` |
| `Html2rss.auto_feed_result`     | **unchanged internally**; user-facing **`Html2rss.scrape`** delegates                 |
| `Html2rss.batch_auto_feed`      | **deleted** → `Html2rss.batch_scrape`                                                 |
| `Batch.inspect_urls`            | `Batch.batch_inspect`                                                                 |
| `Batch.scrape_urls`             | `Batch.batch_scrape`                                                                  |
| —                               | `Batch.batch_recon`, `Html2rss.batch_recon`, `Html2rss.batch_inspect`                 |

**Relocations:**

| Before                                  | After                                              |
| --------------------------------------- | -------------------------------------------------- |
| `MCP::Inspect`                          | `PageRecon::Diagnostics`                           |
| `spec/lib/html2rss/mcp/inspect_spec.rb` | `spec/lib/html2rss/page_recon/diagnostics_spec.rb` |

Downstream: update Cursor `user-html2rss` MCP namespace tool names; `html2rss-configs` contributors use CLI `apply` not `feed`.

## [0.19.1](https://github.com/html2rss/html2rss/compare/v0.19.0...v0.19.1) (2026-05-01)

### Bug Fixes

- restore RubyGems release provenance ([#363](https://github.com/html2rss/html2rss/issues/363)) ([bdd7a93](https://github.com/html2rss/html2rss/commit/bdd7a93fab1930ee85420dc49c1cc56e3f175b6e))

## [0.19.0](https://github.com/html2rss/html2rss/compare/v0.18.0...v0.19.0) (2026-05-01)

### Features

- make strategy optional + default to `:auto` with fallback selection & raise on empty feed ([#358](https://github.com/html2rss/html2rss/issues/358)) ([416d000](https://github.com/html2rss/html2rss/commit/416d0006e6f8ee035c78d31ebca75f7364468a5f))
- **scraper:** let wordpress query paginated archives ([#352](https://github.com/html2rss/html2rss/issues/352)) ([c5bb745](https://github.com/html2rss/html2rss/commit/c5bb745756e2c267bf5b919961646b32e10209bc))
- **strategy:** add Botasaurus strategy ([#357](https://github.com/html2rss/html2rss/issues/357)) ([dec6eb6](https://github.com/html2rss/html2rss/commit/dec6eb621a31316c22109ecc9449eccf4383218c))

### Bug Fixes

- allow @ in channel URL paths while rejecting unsafe components ([#359](https://github.com/html2rss/html2rss/issues/359)) ([4f83ace](https://github.com/html2rss/html2rss/commit/4f83aced3a4f4c1abe07c0913c7d074fa826d7db))
- compact Rendering#to_html output ([#351](https://github.com/html2rss/html2rss/issues/351)) ([4a414ce](https://github.com/html2rss/html2rss/commit/4a414ce3f0652ca19d2b632a401042cfd00159a6))

## Changelog
