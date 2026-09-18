# Implementation Plan: deepen-branch-architecture-and-loc-reduction

Intent: inline
Circuit breaker approved: false

<!-- phase:start -->

## Phase 01 — Deepen OptionSpec and eliminate dual-ownership option validation

target_files:

- `lib/html2rss/selectors/option_spec.rb`
- `lib/html2rss/config/selectors_validator.rb`
- `lib/html2rss/selectors/post_processors/base.rb`
- `lib/html2rss/config/issue_mapper.rb`
- `spec/lib/html2rss/selectors/option_spec_spec.rb`

read_context:

- `lib/html2rss/selectors/schema_export.rb`
- `spec/lib/html2rss/config/selectors_validator_spec.rb`
- `spec/lib/html2rss/selectors/post_processors/base_spec.rb`
- `spec/lib/html2rss/config/issue_mapper_spec.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/selectors/option_spec_spec.rb spec/lib/html2rss/config/selectors_validator_spec.rb spec/lib/html2rss/selectors/post_processors/base_spec.rb spec/lib/html2rss/config/issue_mapper_spec.rb`
commit_message: `refactor(selectors): deepen OptionSpec and unify option validation`

<!-- phase:end -->

<!-- phase:start -->

## Phase 02 — Eliminate ExtractorArgs ceremony and simplify extractor strategies

target_files:

- `lib/html2rss/selectors/extractors.rb`
- `lib/html2rss/selectors/extractors/attribute.rb`
- `lib/html2rss/selectors/extractors/href.rb`
- `lib/html2rss/selectors/extractors/html.rb`
- `lib/html2rss/selectors/extractors/static.rb`
- `lib/html2rss/selectors/extractors/text.rb`
- `spec/lib/html2rss/selectors/extractors/attribute_spec.rb`
- `spec/lib/html2rss/selectors/extractors/href_spec.rb`
- `spec/lib/html2rss/selectors/extractors/html_spec.rb`
- `spec/lib/html2rss/selectors/extractors/static_spec.rb`
- `spec/lib/html2rss/selectors/extractors/text_spec.rb`

read_context:

- `lib/html2rss/selectors/extractors/extractor_args.rb`
- `spec/lib/html2rss/selectors/extractors_spec.rb`
- `spec/lib/html2rss/selectors_spec.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/selectors/extractors/ spec/lib/html2rss/selectors/extractors_spec.rb spec/lib/html2rss/selectors_spec.rb`
commit_message: `refactor(selectors): eliminate ExtractorArgs and streamline extractor kwargs`

<!-- phase:end -->

<!-- phase:start -->

## Phase 03 — Eliminate SelectorsValidator dynamic keys workaround and stripped error wrappers

target_files:

- `lib/html2rss/config/selectors_validator.rb`
- `lib/html2rss/config/validator.rb`
- `spec/lib/html2rss/config/selectors_validator_spec.rb`

read_context:

- `spec/lib/html2rss/config/validator_spec.rb`
- `spec/lib/html2rss/config/issue_mapper_spec.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/config/selectors_validator_spec.rb spec/lib/html2rss/config/validator_spec.rb spec/lib/html2rss/config_spec.rb`
commit_message: `refactor(config): remove SelectorsValidator nesting workaround and stripped error wrappers`

<!-- phase:end -->

<!-- phase:start -->

## Phase 04 — Inline Config::Preparer and eliminate legacy Config.validate_yaml

target_files:

- `lib/html2rss/config.rb`
- `spec/lib/html2rss/config_spec.rb`

read_context:

- `spec/lib/html2rss/config/validator_spec.rb`
- `lib/html2rss.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/config_spec.rb spec/lib/html2rss/config/validator_spec.rb`
commit_message: `refactor(config): inline Preparer defaults and purge dead validate_yaml`

<!-- phase:end -->

<!-- phase:start -->

## Phase 05 — Deepen Test::Policy outcome evaluation and drop PipelineOptions parameter bag

target_files:

- `lib/html2rss/test.rb`
- `lib/html2rss/test/policy.rb`
- `spec/lib/html2rss/test_spec.rb`

read_context:

- `spec/lib/html2rss/test/policy_spec.rb`
- `spec/lib/html2rss/test/enhance_audit_spec.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/test_spec.rb`
commit_message: `refactor(test): deepen Policy outcome evaluation and eliminate PipelineOptions bag`

<!-- phase:end -->

<!-- phase:start -->

## Phase 06 — Streamline JsonXml and StepEnv environment wiring

target_files:

- `lib/html2rss/selectors/json_xml.rb`
- `lib/html2rss/selectors/step_env.rb`
- `lib/html2rss/selectors/item_env.rb`
- `spec/lib/html2rss/selectors/json_xml_spec.rb`

read_context:

- `spec/lib/html2rss/selectors_spec.rb`
- `lib/html2rss/selectors.rb`

verification_gate: `bundle exec rspec spec/lib/html2rss/selectors/json_xml_spec.rb spec/lib/html2rss/selectors_spec.rb`
commit_message: `refactor(selectors): simplify JsonXml module functions and StepEnv delegation`

<!-- phase:end -->

<!-- phase:start -->

## Phase 07 — Remove deleted ExtractorArgs file, full quality gate, docs, and changelog sync

target_files:

- `lib/html2rss/selectors/extractors/extractor_args.rb`
- `CHANGELOG.md`
- `lib/html2rss/selectors/README.md`
- `CONTEXT.md`

read_context:

- `bin/ready`
- `Makefile`

verification_gate: `bin/ready`
commit_message: `chore(core): finalize architectural deepening, prune dead files, and sync docs`

<!-- phase:end -->
