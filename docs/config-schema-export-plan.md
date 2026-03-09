# Config Schema Export Plan

## Context

The current branch started two useful changes:

- generate a JSON Schema from the runtime `dry-validation` contracts
- check in the generated schema so clients can validate config before runtime

That direction is correct and should not change. The implementation needs to stay anchored to these product goals:

1. `dry-validation` remains the primary source of truth for config rules.
2. html2rss exports a JSON Schema for client-side, editor, and tool usage.
3. the exported schema stays easy to discover for humans and AI tools.
4. the shipped schema stays in sync with code through tests and CI.

## Why This Matters

There are two separate audiences for this schema:

- humans: gem users want an obvious command and a stable file path
- tools: editors, scripts, and AI agents want a machine-readable artifact with a predictable location

The schema should therefore be both:

- generated at runtime from the validator where possible
- published as a checked-in JSON file that ships with the gem

## Current Gaps

### P1: generated artifact drift

The committed schema at [`schema/html2rss-config.schema.json`](/Users/gil/versioned/html2rss/html2rss/schema/html2rss-config.schema.json) is out of date relative to the generator, so the CI diff gate in [`.github/workflows/lint_and_test.yml`](/Users/gil/versioned/html2rss/html2rss/.github/workflows/lint_and_test.yml) fails once the schema is regenerated.

### P2: selector reference arrays are under-specified

The runtime validator in [`lib/html2rss/selectors/config.rb`](/Users/gil/versioned/html2rss/html2rss/lib/html2rss/selectors/config.rb) rejects empty `guid` and `categories` arrays, but the generator in [`support/development/config_schema.rb`](/Users/gil/versioned/html2rss/html2rss/support/development/config_schema.rb) does not yet encode that rule in JSON Schema.

More generally, runtime-only cross-field rules such as "array elements must reference sibling selector keys" may not map cleanly into JSON Schema. Runtime validation remains authoritative for those cases.

## Design Goals

### 1. Public runtime API

Schema export should be a supported capability of the gem, not only a development helper.

Preferred API:

- `Html2rss::Config.json_schema`
- optional convenience methods:
  - `Html2rss::Config.json_schema_json`
  - `Html2rss::Config.schema_path`

This allows Ruby callers, CLIs, and automation to use one supported code path.

### 2. Human-friendly CLI

Expose the schema via the executable so users do not need to know about rake tasks or internal files.

Preferred command shape:

- `html2rss schema`

Expected behavior:

- print schema JSON to stdout by default
- support pretty output
- optionally support writing to a destination path

### 3. Stable packaged artifact

Keep a canonical checked-in JSON file at:

- [`schema/html2rss-config.schema.json`](/Users/gil/versioned/html2rss/html2rss/schema/html2rss-config.schema.json)

This file should be included in the gem package so external tools can rely on a stable path after installation.

### 4. Single generation path

Rake, CLI, specs, and CI should all use the same public schema generation entrypoint. Avoid separate ad hoc generation logic.

## File-Level Delivery Plan

### Move generator into `lib/`

Move schema generation logic out of development-only support code and into a runtime path.

Files:

- move logic from [`support/development/config_schema.rb`](/Users/gil/versioned/html2rss/html2rss/support/development/config_schema.rb)
- new runtime home: `lib/html2rss/config/schema.rb`
- ensure it is required from [`lib/html2rss/config.rb`](/Users/gil/versioned/html2rss/html2rss/lib/html2rss/config.rb) or a nearby load point

Outcome:

- schema generation becomes a supported library feature

### Expose public `Config` API

Add a public method on `Html2rss::Config` that returns the generated schema hash.

Files:

- [`lib/html2rss/config.rb`](/Users/gil/versioned/html2rss/html2rss/lib/html2rss/config.rb)
- `lib/html2rss/config/schema.rb`

Outcome:

- Ruby consumers and internal tasks call the same public API

### Add CLI entrypoint

Expose schema export from the existing Thor CLI.

Files:

- [`lib/html2rss/cli.rb`](/Users/gil/versioned/html2rss/html2rss/lib/html2rss/cli.rb)
- `exe/` wrapper if needed

Outcome:

- humans and automation can discover and export the schema easily

### Keep and package the generated schema file

Preserve the canonical generated artifact under `schema/` and include it in the gem.

Files:

- [`schema/html2rss-config.schema.json`](/Users/gil/versioned/html2rss/html2rss/schema/html2rss-config.schema.json)
- [`html2rss.gemspec`](/Users/gil/versioned/html2rss/html2rss/html2rss.gemspec)

Outcome:

- the schema is available to downstream tooling after gem installation

### Update generation task to use the public API

The rake task should call the runtime schema API, not a development-only module.

Files:

- [`lib/tasks/config_schema.rake`](/Users/gil/versioned/html2rss/html2rss/lib/tasks/config_schema.rake)

Outcome:

- one generation path for local use and CI

### Fix P2 in exported schema

Add `minItems: 1` for `guid` and `categories` in the exported schema overlay.

Files:

- `lib/html2rss/config/schema.rb`
- [`lib/html2rss/selectors/config.rb`](/Users/gil/versioned/html2rss/html2rss/lib/html2rss/selectors/config.rb) for parity review only

Outcome:

- exported JSON Schema catches the same non-empty array rule as runtime validation

### Tighten specs around generation and packaging

Add tests that fail when the schema drifts or loses important runtime-derived constraints.

Files:

- [`spec/lib/html2rss/config/schema_spec.rb`](/Users/gil/versioned/html2rss/html2rss/spec/lib/html2rss/config/schema_spec.rb)
- add or extend packaging tests if needed

Recommended assertions:

- `auto_source.scraper.microdata` appears in the generated schema
- `guid.minItems == 1`
- `categories.minItems == 1`
- the packaged JSON file matches the current generated schema

Outcome:

- the regression that caused `P1` is caught before CI or release

### Keep CI freshness enforcement

The CI gate is still valuable once generation is routed through the public API and the committed artifact is regenerated.

Files:

- [`.github/workflows/lint_and_test.yml`](/Users/gil/versioned/html2rss/html2rss/.github/workflows/lint_and_test.yml)

Outcome:

- checked-in schema remains synchronized with the codebase

## Explicit Non-Goals

- move the schema artifact under `spec/`
- rely only on a development helper under `support/`
- promise that JSON Schema can represent every runtime cross-field rule exactly

`spec/` is the wrong home for a user-facing artifact. It is test-only by convention, harder to discover, and not an appropriate packaged location for downstream clients.

## Suggested Implementation Order

1. Move schema generation to `lib/html2rss/config/schema.rb`.
2. Add `Html2rss::Config.json_schema`.
3. Update the rake task to use the public API.
4. Add a CLI command for schema export.
5. Update the gemspec so `schema/html2rss-config.schema.json` is packaged.
6. Add `minItems: 1` to `guid` and `categories`.
7. Regenerate and commit the schema artifact.
8. Tighten specs for generated content and packaged artifact parity.
9. Keep the CI diff gate enabled.

## Success Criteria

This work is complete when:

- `Html2rss::Config.json_schema` returns the current schema
- `html2rss schema` exposes the schema for humans and automation
- `schema/html2rss-config.schema.json` is regenerated from the same code path
- the schema file is packaged in the gem
- CI passes without post-generation diff
- the exported schema enforces non-empty `guid` and `categories` arrays
- the documentation clearly points users to the API, CLI, and packaged file
