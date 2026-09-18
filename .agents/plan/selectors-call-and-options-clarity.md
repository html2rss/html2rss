# Implementation Plan: selectors-call-and-options-clarity

Intent: `.agents/compile/selectors-call-and-options-clarity.yaml`
Circuit breaker approved: false

## Classification & Architecture

- **Classification:** `design` (`refactor-types` / `deep-modules` for vocabulary, call ownership clarity, and hull code elimination)
- **Runtime:** `ruby-dev` (plain Ruby gem, Ruby 4 baseline)
- **Compat:** Zero backward compatibility, no legacy, no snowflakes, no hull codes for compat. Breaking Ruby API for `StepEnv` member rename (`options` → `step_config`) with no shims. Wire YAML and MCP contracts remain strictly unchanged.

<!-- phase:start -->

## Phase 01 — Disambiguate step_config, purge hull methods, and eliminate spec snowflakes

Disambiguate the Ruby vocabulary between static option specifications (`OptionSpec` / strategy `OPTIONS`) and runtime YAML step hashes, purge legacy hull methods, and remove snowflake methods from specs:
- Update `Html2rss::Selectors::StepEnv` definition from `:options` to `:step_config`. Default `step_config` to `{}.freeze` in `initialize`. No backward compat alias for `options`.
- Update `ItemEnv#context_for(step_config:)` to require `step_config:` keyword with no `options:` fallback.
- Update `Selectors#post_process` to pass `step_config:`.
- Purge duplicate hull method `PostProcessors::Base.strategy_options`; call `OptionSpec.for(self)` directly in `validate_options!`.
- Purge wrapper hull method `SchemaExport.options_for(klass)`; call `OptionSpec.for(klass)` directly in `post_processor_properties` and `post_processor_required`.
- Modernize `Extractors.call(config, xml)`: rename legacy `attribute_options` parameter to `config`.
- Update `PostProcessors::Base`, `Substring`, `Gsub`, `Template`, and `SanitizeHtml` to access `context.step_config`.
- Refactor `SanitizeHtml`: extract pure `SanitizeHtml.sanitize(html, base_url)` method; instance `#call` delegates to it, and `SanitizeHtml.call(html, url)` checks fragment cache and calls `self.sanitize` directly without fabricating a fake `StepEnv` object.
- Remove snowflake helper `def context_for(options)` in `gsub_spec.rb` and `substring_spec.rb` in conformance with `AGENTS.md` ("Do not define methods within _spec.rb files"); use standard `let` / inline `StepEnv.new(step_config:)`.
- Update all post-processor specs constructing `StepEnv.new(options: ...)` to `StepEnv.new(step_config: ...)`.

target_files:

- `lib/html2rss/selectors/step_env.rb`
- `lib/html2rss/selectors/item_env.rb`
- `lib/html2rss/selectors.rb`
- `lib/html2rss/selectors/post_processors/base.rb`
- `lib/html2rss/selectors/schema_export.rb`
- `lib/html2rss/selectors/extractors.rb`
- `lib/html2rss/selectors/post_processors/substring.rb`
- `lib/html2rss/selectors/post_processors/gsub.rb`
- `lib/html2rss/selectors/post_processors/template.rb`
- `lib/html2rss/selectors/post_processors/sanitize_html.rb`
- `spec/lib/html2rss/selectors/post_processors/base_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/gsub_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/markdown_to_html_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/parse_time_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/parse_uri_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/sanitize_html_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/substring_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/template_spec.rb`
- `spec/lib/html2rss/selectors/post_processors_spec.rb`

read_context:

- `lib/html2rss/selectors/option_spec.rb`
- `lib/html2rss/html/rendering/description_builder.rb`
- `spec/lib/html2rss/selectors_spec.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/selectors/`
commit_message: `refactor(selectors)!: disambiguate step_config and purge hull methods`

<!-- phase:end -->

<!-- phase:start -->

## Phase 02 — Clarify #call ownership taxonomy and helper entry points

Establish a crystal-clear reading story and taxonomy for `#call` and `.call` across registries, strategies, and helpers:
- Add `JsonXml.call(object)` class convenience method (`def self.call(object) = new(object).call`) and document its role as an internal JSON-to-XML data converter helper.
- Update `Selectors#build_parsed_body` to invoke `JsonXml.call(page_response.parsed_body)` directly (`selectors.rb` modified again after Phase 01 to adopt `JsonXml.call`).
- Add explicit YARD documentation on `Extractors.call` documenting it as the registry dispatcher (`extractors.rb` modified again after Phase 01 parameter rename).
- Add explicit YARD documentation on `PostProcessors.call` documenting it as the registry dispatcher.
- Add YARD documentation on `SanitizeHtml.call(html, url)` explaining its role as a cached standalone helper for non-selector HTML sanitization vs `#call` as the post-processor instance method (`sanitize_html.rb` modified again after Phase 01 refactor).
- Update `lib/html2rss/selectors/README.md` with "The Three Layers of #call" section (Registry Dispatchers, Strategy Execution, and Specialized Helpers) and update diagrams to reflect `step_config`.
- Update `CONTEXT.md` vocabulary diagram and narrative to reflect `step_config` and `#call` ownership clarity.

target_files:

- `lib/html2rss/selectors/json_xml.rb`
- `lib/html2rss/selectors.rb`
- `lib/html2rss/selectors/extractors.rb`
- `lib/html2rss/selectors/post_processors.rb`
- `lib/html2rss/selectors/post_processors/sanitize_html.rb`
- `lib/html2rss/selectors/README.md`
- `CONTEXT.md`

read_context:

- `lib/html2rss/selectors/step_env.rb`
- `lib/html2rss/html/rendering/description_builder.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/selectors/`
commit_message: `docs(selectors): clarify call ownership taxonomy and step config`

<!-- phase:end -->

<!-- phase:start -->

## Phase 03 — Record breaking changes, verify YARD docs, and enforce readiness

Document the Ruby API breaking change in `CHANGELOG.md`, verify absence of stale public references, regenerate YARD docs, and run the full repo readiness suite:
- In `CHANGELOG.md`, record under `## Unreleased` -> `### Breaking`:
  - `StepEnv#options` renamed to `step_config` and `ItemEnv#context_for(step_config:)` with no backward compat shims.
  - Purged hull methods: `PostProcessors::Base.strategy_options` (replaced with direct `OptionSpec.for(self)`) and `SchemaExport.options_for` (replaced with direct `OptionSpec.for(klass)`).
  - Emphasize wire invariants: YAML selectors/post_process/extractors and `Html2rss::Selectors` class name remain strictly unchanged.
- Run `make ready` (`bin/ready`), ensuring `lint`, `lint-yard`, `test`, `schema`, `validate-fixtures`, `docs`, and `shellcheck` pass cleanly with exit code 0.

target_files:

- `CHANGELOG.md`

read_context:

- `lib/html2rss/selectors/README.md`
- `CONTEXT.md`
- `Makefile`

verification_gate: `bin/ready`
commit_message: `docs(selectors): record step_config breaking change and verify YARD docs`

<!-- phase:end -->
