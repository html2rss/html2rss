# Implementation Plan: extensive-quality-loop-modern-ruby

Intent: inline
Circuit breaker approved: false

<!-- phase:start -->

## Phase 01 — Eliminate spec snowflakes and send calls in test suite

Enforce repo testing standards (AGENTS.md & ruby-dev):
- Eliminate `Html2rss.send(:reset_defaults!)` in `spec/lib/html2rss/defaults_spec.rb` by making `Html2rss.reset_defaults!` a public class method with YARD docs (`@return [void]`).
- Eliminate `described_class.send(:baseline_request_budget_for, config)` in `spec/lib/html2rss/feed_pipeline/runtime_policy_spec.rb` by promoting `baseline_request_budget_for` to a public class method on `Html2rss::FeedPipeline::RuntimePolicy` with YARD documentation.
- Eliminate top-level `def ...` method definitions inside `_spec.rb` files (violating AGENTS.md) across:
  - `spec/lib/html2rss/scoring/container_assessor_spec.rb` (`def build_node` -> `let`)
  - `spec/lib/html2rss/link_destination/path_classifier_spec.rb` (`def classifier_for` -> `let`)
  - `spec/lib/html2rss/auto_source/segmenter_spec.rb` (`def document_for` -> `let`)
  - `spec/lib/html2rss/request_service/blocked_surface_spec.rb` (`def challenge_fixture` -> helper in `spec/support/helpers/`)
  - `spec/lib/html2rss/feed_resolution/scorer_spec.rb` (`def assessment`, `def scored` -> `let` / helper module)
  - `spec/lib/html2rss/syndication/discovery_spec.rb` (`def response` -> `let`)
  - `spec/lib/html2rss/test/enhance_audit_spec.rb` (`def response_for`, `def probe` -> `let`)
  - `spec/lib/html2rss/scoring/engine_spec.rb` (`def build_node`, `def build_segment`, `def article_segment` -> helper module)
  - `spec/lib/html2rss/auto_source/cleanup_spec.rb` (`def rss_item` -> `let`)
  - `spec/lib/html2rss/auto_source/scraper/sitemap_spec.rb` and `json_state_spec.rb` (snowflake helpers -> `let` / helper module)
  - `spec/lib/html2rss/capture_spec.rb` (`def html_response`, `def stub_outcome` -> helper module)
  - `spec/lib/html2rss/mcp/outcome_spec.rb` and `server_spec.rb` (`def report`, `def recon_result`, `def test_result` -> helper module)

target_files:

- `lib/html2rss.rb`
- `lib/html2rss/feed_pipeline/runtime_policy.rb`
- `spec/lib/html2rss/defaults_spec.rb`
- `spec/lib/html2rss/feed_pipeline/runtime_policy_spec.rb`
- `spec/support/helpers/spec_fixture_helpers.rb`
- `spec/spec_helper.rb`
- `spec/lib/html2rss/scoring/container_assessor_spec.rb`
- `spec/lib/html2rss/link_destination/path_classifier_spec.rb`
- `spec/lib/html2rss/auto_source/segmenter_spec.rb`
- `spec/lib/html2rss/request_service/blocked_surface_spec.rb`
- `spec/lib/html2rss/feed_resolution/scorer_spec.rb`
- `spec/lib/html2rss/syndication/discovery_spec.rb`
- `spec/lib/html2rss/test/enhance_audit_spec.rb`
- `spec/lib/html2rss/scoring/engine_spec.rb`
- `spec/lib/html2rss/auto_source/cleanup_spec.rb`
- `spec/lib/html2rss/auto_source/scraper/sitemap_spec.rb`
- `spec/lib/html2rss/auto_source/scraper/json_state_spec.rb`
- `spec/lib/html2rss/capture_spec.rb`
- `spec/lib/html2rss/mcp/outcome_spec.rb`
- `spec/lib/html2rss/mcp/server_spec.rb`

read_context:

- `AGENTS.md`
- `spec/support/helpers/example_helpers.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/defaults_spec.rb spec/lib/html2rss/feed_pipeline/runtime_policy_spec.rb spec/lib/html2rss/scoring/ spec/lib/html2rss/mcp/`
commit_message: `refactor(spec): eliminate send calls and def snowflakes in specs`

<!-- phase:end -->

<!-- phase:start -->

## Phase 02 — Refactor Test#call complexity and resolve code smells

Refactor bloated methods and code smells (boy-scouting):
- In `lib/html2rss/test.rb`:
  - Decompose 27-statement `Test#call` into focused single-purpose methods (≤10 lines per AGENTS.md):
    - `execute_timed_pipeline(raw_config)`
    - `evaluate_outcome(...)`
    - `build_test_result(...)`
  - Remove all 5 disabled RuboCop metrics (`Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity`) and resolve Reek `TooManyStatements`.
- In `lib/html2rss/mcp/server.rb`:
  - Replace repeated `%i[stdio http]` allocation with frozen constant `TRANSPORTS = Set[:stdio, :http].freeze`.
- In `lib/html2rss/defaults.rb`:
  - Modernize log level symbol checks with `VALID_LOG_LEVELS` set.

target_files:

- `lib/html2rss/test.rb`
- `lib/html2rss/mcp/server.rb`
- `lib/html2rss/defaults.rb`

read_context:

- `lib/html2rss/test/policy.rb`
- `lib/html2rss/test/enhance_audit.rb`
- `spec/lib/html2rss/test_spec.rb`
- `spec/lib/html2rss/mcp/server_spec.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/test_spec.rb spec/lib/html2rss/mcp/server_spec.rb spec/lib/html2rss/defaults_spec.rb`
commit_message: `refactor(test): decompose Test#call and eliminate disabled metrics`

<!-- phase:end -->

<!-- phase:start -->

## Phase 03 — Modern Ruby syntax and collection idioms

Modernize Ruby syntax and collection idioms based on user target selection:
- Modernize argument forwarding and block forwarding in `lib/html2rss/recon.rb` and `lib/html2rss/sst/node.rb`.
- Modernize collection scanning and iteration idioms across `lib/html2rss/`.
- If Ruby 4.0 baseline is selected:
  - Update `.rubocop.yml` to `TargetRubyVersion: 4.0` (and gemspec if approved).
  - Adopt `Style/ItBlockParameter` (`it`) across `lib/` and `spec/`.
  - Adopt anonymous block forwarding `(&)` and keyword forwarding `(**)`.
- If Ruby 3.3 compatibility is preserved:
  - Keep `.rubocop.yml` at `TargetRubyVersion: 3.3`.
  - Apply clean modern Ruby 3.3 idioms (endless methods, pattern matching, Data.define, frozen Set literals).

target_files:

- `lib/html2rss/recon.rb`
- `lib/html2rss/sst/node.rb`
- `.rubocop.yml`

read_context:

- `.tool-versions`
- `html2rss.gemspec`
- `AGENTS.md`

verification_gate: `bin/lint-changed && bundle exec rspec spec/lib/html2rss/recon_spec.rb spec/lib/html2rss/sst/node_spec.rb`
commit_message: `refactor(core): modernize ruby idioms and block forwarding`

<!-- phase:end -->

<!-- phase:start -->

## Phase 04 — Full readiness verification, documentation and changelog sync

Run the comprehensive PR readiness gate and document changes:
- Run `bin/ready` (`make -j 6 lint lint-yard test schema validate-fixtures docs shellcheck`).
- Run `bundle exec reek` to confirm no new code smells.
- Update `CHANGELOG.md` under `## Unreleased` summarizing boy-scout improvements, spec cleanup, and modernizations.

target_files:

- `CHANGELOG.md`

read_context:

- `Makefile`
- `bin/ready`

verification_gate: `bin/ready`
commit_message: `docs(changelog): record quality loop and modern ruby improvements`

<!-- phase:end -->
