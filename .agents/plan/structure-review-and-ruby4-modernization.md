# Implementation Plan: structure-review-and-ruby4-modernization

Intent: inline
Circuit breaker approved: false

<!-- phase:start -->

## Phase 01 — Eliminate snowflakes, obsolete requires, and struct legacy

Clean up architectural snowflakes and dead code:
- Remove obsolete `require 'set' # rubocop:disable Lint/RedundantRequireStatement` from `lib/html2rss/article/deduplicator.rb`.
- Add `lib/html2rss/doctor.rb` defining the `Html2rss::Doctor` module with YARD documentation, bringing `doctor/` into conformity with every other namespace in `lib/html2rss/`.
- Unify private method visibility in `lib/html2rss/page_recon/diagnostics.rb` and `lib/html2rss/cli/validate.rb` to use clean `class << self; private` or standard private class methods instead of snowflake `module_function :foo` + `private_class_method :foo`.
- Migrate `Selectors::Context` in `lib/html2rss/selectors.rb` from `Struct.new` to `Data.define(:options, :item, :config, :scraper, :item_scope)`.
- Update `.gitignore` to ignore `.byebug_history`.

target_files:

- `lib/html2rss/article/deduplicator.rb`
- `lib/html2rss/doctor.rb`
- `lib/html2rss/page_recon/diagnostics.rb`
- `lib/html2rss/cli/validate.rb`
- `lib/html2rss/selectors.rb`
- `.gitignore`

read_context:

- `lib/html2rss/doctor/botasaurus.rb`
- `lib/html2rss/selectors/item_scope.rb`
- `lib/html2rss/page_recon.rb`
- `lib/html2rss/cli.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/article/deduplicator_spec.rb spec/lib/html2rss/doctor/botasaurus_spec.rb spec/lib/html2rss/page_recon/diagnostics_spec.rb spec/lib/html2rss/selectors_spec.rb`
commit_message: `refactor(core): remove snowflakes, obsolete requires, and struct legacy`

<!-- phase:end -->

<!-- phase:start -->

## Phase 02 — Modernize with Ruby 4 C-backed Set and frozen sets

Upgrade collection constants to direct Ruby 4 `Set[...]` literals and convert membership search arrays into frozen Sets:
- In `lib/html2rss/defaults.rb`: change `VALID_LOG_LEVELS` to `Set[:debug, :info, :warn, :error, :fatal, :unknown].freeze`.
- In `lib/html2rss/error.rb`: change `SURFACE_HINT_CATEGORIES` to `Set[:app_shell, :blocked_surface, :high_entropy_surface].freeze`.
- In `lib/html2rss/request_service/botasaurus_contract.rb`: convert `EXECUTION_MODES`, `NAVIGATION_MODES`, `ERROR_CATEGORIES` to frozen Sets.
- In `lib/html2rss/auto_source/scraper.rb`: convert `HEURISTIC_SCRAPERS`, `REQUEST_SESSION_SCRAPERS`, `CAPTURED_RESPONSE_SCRAPERS` to frozen Sets.
- In `lib/html2rss/sst/tags.rb` and `lib/html2rss/sst/normalizer.rb`: replace `%i[...].to_set.freeze` with `Set[...]` literals.
- In `lib/html2rss/link_destination/path_classifier.rb`: replace `%w[...].to_set.freeze` with `Set[...]` literals in `SEGMENT_SETS`.
- In `lib/html2rss/html/sst_article_extractor.rb`: convert `FALLBACK_HEADING_NAMES` and `CATEGORY_CONTAINER_NAMES` to `Set[...]`.
- In `lib/html2rss/html/navigator.rb`: modernize `HEADING_TAGS`, `IGNORED_CONTAINER_TAGS`, `UTILITY_LANDMARK_TAGS`, `CARD_WALK_STOP_TAGS` to `Set[...]` literals.
- In `lib/html2rss/config/validator.rb`: convert `DIRECTORY_TOPICS` to `Set[...]` for $O(1)$ membership checks in `capture.rb`.

target_files:

- `lib/html2rss/defaults.rb`
- `lib/html2rss/error.rb`
- `lib/html2rss/request_service/botasaurus_contract.rb`
- `lib/html2rss/auto_source/scraper.rb`
- `lib/html2rss/sst/tags.rb`
- `lib/html2rss/sst/normalizer.rb`
- `lib/html2rss/link_destination/path_classifier.rb`
- `lib/html2rss/html/sst_article_extractor.rb`
- `lib/html2rss/html/navigator.rb`
- `lib/html2rss/config/validator.rb`

read_context:

- `lib/html2rss/capture.rb`
- `lib/html2rss/html/article_rules/description.rb`
- `lib/html2rss/link_destination/noise_policy.rb`
- `lib/html2rss/scoring/engine.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/defaults_spec.rb spec/lib/html2rss/request_service/botasaurus_contract_spec.rb spec/lib/html2rss/sst/normalizer_spec.rb spec/lib/html2rss/link_destination/path_classifier_spec.rb spec/lib/html2rss/config/validator_spec.rb`
commit_message: `perf(collections): modernize with ruby 4 c-backed set and frozen sets`

<!-- phase:end -->

<!-- phase:start -->

## Phase 03 — Eliminate descendant array churn and optimize hotpath traversal

Address the primary source of 721k+ allocations discovered in baseline profiling:
- In `lib/html2rss/html/sst_article_extractor.rb`: replace `ancestor.descendants.any? { |d| d.equal?(child) }` with `Index.for_node(child)&.descendant_of?(child, ancestor)` or parent walk, eliminating massive nested subtree array allocations.
- In `lib/html2rss/sst/node.rb`: add non-allocating traversal / counting method `count_descendants` and replace `descendants.count(&:link?)` in `Node#text_density`.
- In `lib/html2rss/auto_source/segmenter/list.rb`:
  - Replace `node.descendants.count(&:link?)` with non-allocating count.
  - Define `BOUNDARY_TAGS = Set[:body, :html].freeze` instead of creating `%i[body html]` array on every parent step.
- In `lib/html2rss/sst/index.rb`, `lib/html2rss/scoring/container_assessor.rb`, `lib/html2rss/sst/node.rb`, `lib/html2rss/link_destination/noise_policy.rb`: replace `text.to_s.scan(/\p{Alnum}+/).size` with a zero-allocation word counter (using block scan `scan(/\p{Alnum}+/) { count += 1 }` or `word_count_at_least?`).
- In `lib/html2rss/auto_source/segmenter.rb`: optimize `landmark_ancestor?` cache keys to avoid allocating 2-element array `[anchor.object_id, container.object_id]` per call.

target_files:

- `lib/html2rss/html/sst_article_extractor.rb`
- `lib/html2rss/sst/node.rb`
- `lib/html2rss/sst/index.rb`
- `lib/html2rss/auto_source/segmenter/list.rb`
- `lib/html2rss/auto_source/segmenter.rb`
- `lib/html2rss/scoring/container_assessor.rb`
- `lib/html2rss/link_destination/noise_policy.rb`

read_context:

- `lib/html2rss/auto_source/cleanup.rb`
- `lib/html2rss/scoring/link_resolver.rb`
- `bin/heuristic-perf-baseline`

verification_gate: `bin/heuristic-perf-baseline && bundle exec rspec spec/lib/html2rss/auto_source/segmenter/list_spec.rb spec/lib/html2rss/sst/node_spec.rb spec/lib/html2rss/html/sst_article_extractor_spec.rb`
commit_message: `perf(auto_source): eliminate descendant array churn and optimize hotpath traversal`

<!-- phase:end -->

<!-- phase:start -->

## Phase 04 — Verification, benchmarking, and documentation sync

Verify full test suite, linting, YARD compliance, and record the updated performance baseline:
- Run `bin/heuristic-perf-baseline --write spec/perf/baseline-auto-source.md` and commit the new baseline.
- Run `bin/rubocop` and `bin/lint-changed` to confirm zero lint offenses with Ruby 4 target.
- Run `bundle exec yard-lint lib/` to ensure all modified public methods maintain strict YARD tags.
- Run full test suite `COVERAGE=true bundle exec rspec`.

target_files:

- `spec/perf/baseline-auto-source.md`

read_context:

- `Makefile`
- `AGENTS.md`
- `spec/perf/`

verification_gate: `bin/ready`
commit_message: `chore(perf): record ruby 4 performance baseline and update documentation`

<!-- phase:end -->
