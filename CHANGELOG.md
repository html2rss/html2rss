# Changelog

## Unreleased

### Breaking

- **Config validation returns `Config::ValidationReport`** (not Dry::Validation::Result / duck-compat `ValidationResult`):
  - `Html2rss.validate` / `Config.validate` / `resolve_and_validate` return `{ success:, issues: [...] }` via `ValidationReport#to_h`.
  - Each issue is `{ path:, code:, message:, expected:, actual: }` (`ValidationIssue`); closed codes: `missing_key`, `type_mismatch`, `unknown_value`, `invalid_value`, `constraint`, `parse`.
  - MCP `validate` payload uses `issues` only (removed nested `errors:`). `Test::Result` uses `validation_issues` (removed `validation_errors` nest). Bump `mcp_contract_version` to **3** — refresh `tools/list`.
  - Nested selector failures keep leaf paths (e.g. `selectors.items.pagination`) instead of flattening prose under `:selectors`.
- **JSON Schema facades relocated** to `Config::Schema` (no thin delegates on `Config`):
  - `Config.json_schema` / `Config.json_schema_json` / `Config.schema_path` → `Config::Schema.json_schema` / `Config::Schema.json_schema_json` / `Config::Schema.path`.
  - `Html2rss.schema_json` updated to call `Config::Schema`.
- **Selectors vocabulary clarity & hull cleanup** (Breaking Ruby API; YAML / MCP wire unchanged — `selectors`, `extractor`, `post_process`):
  - Renamed `StepEnv#options` to `StepEnv#step_config` (and `ItemEnv#context_for(step_config:)`), eliminating collision with `OptionSpec` strategy introspection. No backward compatibility shims.
  - Purged duplicate hull method `PostProcessors::Base.strategy_options` in favor of direct `OptionSpec.for(self)`.
  - Purged wrapper hull method `SchemaExport.options_for` in favor of direct `OptionSpec.for(klass)`.
  - Modernized `Extractors.call(config, xml)` parameter from legacy `attribute_options` to `config`.
  - Modernized `SanitizeHtml`: extracted pure `SanitizeHtml.sanitize(html, base_url)` method; `SanitizeHtml.call(html, url)` no longer allocates a fake `StepEnv` hull object.
  - Added `JsonXml.call(object)` class-level convenience converter method.
  - Clarified `#call` ownership taxonomy: registry dispatchers (`Extractors.call`/`PostProcessors.call`), strategy execution (`#call`), and helpers (`JsonXml.call`/`SanitizeHtml.call`).
- **Selectors vocabulary cutover** (Breaking Ruby API; YAML / MCP wire unchanged — `selectors`, `extractor`, `post_process`):
  - Folded `CategoriesExtractor` and `AttributeSelector` into private field dispatch on `Selectors` (no `FieldSelect`).
  - Renamed `ItemScope` → `ItemEnv`, `Context` → `StepEnv` with member `base_url` (not `channel_url` on StepEnv).
  - Renamed `Option` → `OptionSpec` (introspection SoT: `for` / `expectation_for` Ruby-typed); `SchemaDoc` → `SchemaExport` (JSON adapter only); `ObjectToXmlConverter` → `JsonXml`; shared `SelectorArgs` → `ExtractorArgs`.
  - Strategy registries and instances use `#call` / `.call` (no `#get` aliases), including `SanitizeHtml.call(html, url)`.
  - Module guide: `lib/html2rss/selectors/README.md`.
- **Selectors modernization** (Ruby API / schema contract; earlier wave, superseded where names conflict):
  - `gsub` `replacement` accepts `String` or `Hash` (Ruby `String#gsub` hash form); schema / validator follow `Selectors::PostProcessors::Gsub::OPTIONS`.
  - Extractor / post-processor config-facing options are owned as each strategy’s `OPTIONS` Array of `Selectors::OptionSpec` (SoT for validator, `OptionSpec`, `SchemaExport`, and `Base.validate_options!`). Do not reintroduce parallel `OPTION_TYPES` maps.
  - Post-processors that require a fixed extracted Ruby type declare `VALUE_TYPE`; `Base` asserts it (callers no longer introspect).
  - Selector nesting key `:items` is owned once as `Selectors::ITEMS_SELECTOR_KEY` (validator + scraper).
- Removed `html_to_markdown` post-processor and the `reverse_markdown` gem dependency. Configs using `post_process` name `html_to_markdown` now fail validation.

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
