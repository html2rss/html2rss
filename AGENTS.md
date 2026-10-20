# AGENTS.md

Architecture and seam ownership map: `CONTEXT.md`.

## Coding & Architecture Contracts

- Keep `lib/html2rss.rb` as the high-level orchestration entrypoint; do not add `lib/html2rss/README.md`.
- Target Ruby >= 3.3, plain Ruby only (never ActiveSupport), with `# frozen_string_literal: true` in every Ruby file.
- Keep methods <= 10 lines and single-purpose, but prefer direct code over tiny helper methods introduced only to satisfy RuboCop metrics.
- Document every public method with YARD tags (`@param`, `@return`).
- No metaprogramming or reflection in `lib/`, enforced by `Html2rss/NoMetaprogramming`. Never disable it inline; use the closed-set enum pattern (`ALL`, `private_class_method :new`, `self.[]`) and Data-block pattern (`X = Data.define(...)` then `class X ... end`).

## Testing Contracts

- Do not define methods inside `*_spec.rb` files; use helpers or shared examples when needed.
- Never use `send(:method_name)` in specs.
- Tag multi-expectation examples with `:aggregate_failures` (`RSpec/MultipleExpectations`).

## Description & HTML Processing

- Preserve structural block newlines (`\n`, `\n\n`) and lists. Protect newlines with `__NEWLINE_PLACEHOLDER__` before horizontal whitespace collapsing (`gsub(/\s+/, ' ')`) and restore them afterward.
- Collapse consecutive wrapping whitespace (including line breaks) inside raw HTML text nodes to a single space.
- Exclude heading elements (`h1..h6`) and the selected read-more/permalink anchor (`a`) when extracting visible article description text.
- New junk title patterns require a fixture with expected **reason**; prefer fixing extractor title provenance when a reason keeps firing.

## Curation CLI / MCP

User/agent surfaces (CLI, MCP, `next_step`, contributor docs) share seven verbs (`inspect`, `recon`, `capture`, `validate`, `test`, `apply`, `scrape`) plus batch variants (`batch_inspect`, `batch_recon`, `batch_scrape`). Canonical contract: `CONTEXT.md` § Frozen contract. Module guide: `lib/html2rss/mcp/README.md`. When verbs change, update `CONTEXT.md` § Frozen contract, this section, `README.md`, and `lib/html2rss/mcp/README.md`.

- **Enhance audit:** `selectors.items.enhance` enriches matched item nodes via `Html::ArticleExtractor`. `Test::EnhanceAudit` owns `quality_report.metrics.enhance_gains` and warn-only enhance warnings; `compare_enhance` on test is diagnostic only. Auto-source-only configs (no selectors) skip `enhance_gains`.
- **Default items selector:** `Selectors::DEFAULT_ITEMS_SELECTOR` expands to `Html::Navigator::MAIN_ANCHOR_SELECTOR` only for that spelling (or blank), applied by `Config.prepare_defaults` only when `selectors:` is present (`CONTEXT.md` § Default items selector).

## Operating Checklist

- Run Ruby, Bundler, Rake, RuboCop, Reek, YARD, and RSpec via `mise exec -- ...` or Make targets (`make quick` for changed-file lint and targeted specs; `make ready` for pre-merge checks).
- When changing config options in `lib/html2rss/selectors/config.rb` or `lib/html2rss/config/validator.rb`, update `lib/html2rss/config/schema.rb` (`Html2rss::Config::Schema`) and run `make schema` to sync `schema/html2rss-config.schema.json`.
- Catalog metadata on `directory` (`title`, `summary`, `topics`) is validated in `DirectoryConfig`. When changing rules, run `make schema` and coordinate `html2rss-configs` validation plus `Html2rss::Configs::Catalog`.
- Keep YARD lint clean without baseline/todo suppression files. `docs/` is generated YARD HTML only (`make docs` / `make clean`); never commit source markdown there.
- `CHANGELOG.md` is the 0.19.x archive; release notes are GitHub Releases (release-drafter).
- Keep living module guides at `lib/html2rss/{auto_source,capture,feed_pipeline,mcp,selectors}/README.md`, wired via `{include:file:lib/.../README.md}` on the owning class. Never add them to `.yardopts --files` (all `README.md` extra files emit `file.README.html` and clobber the gem README).
- Zeitwerk ignores `.md`. `lib/html2rss/capture/` may contain only `README.md`; do not add a nested `capture.rb`.

## Release

- After merging a PR to `master` or when shipping, ask whether to bump and which version unless already specified; never invent the version.
- Dispatch `.github/workflows/bump-version.yml` on `master` only after the user answers (`bump_type`: `auto`, `patch`, `minor`, `major`, or `custom`; pass `custom_version` only when `bump_type` is `custom`).
- Wait for the workflow run to bump `lib/html2rss/version.rb`, regenerate the config schema, and open `release/vX.Y.Z` (`chore(release): bump version to vX.Y.Z`).
- Merge `release/vX.Y.Z` (squash or rebase only; merge commits are disabled on `master`) only when asked and after Ruby 3.3, Ruby 3.4, Ruby 4.0, and lint are green.
- Stop after that merge. Publish the draft release (`.github/workflows/release_gem.yml`) only when asked.
