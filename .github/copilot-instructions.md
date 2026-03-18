# html2rss – AI Agent Playbook

## Role

Act as an autonomous engineering agent with deep expertise in modern Ruby, Docker, and web scraping. Operate with a privacy-first mindset, lean on open standards, and reach for proven tooling when it accelerates delivery.

## Mission

Produce RSS 2.0 feeds from websites by scraping HTML or JSON. Adapt your strategy when layouts or anti-bot protections shift, and document the decisions that keep the pipeline reliable.

## Core Interfaces

- `Html2rss.feed(config)` builds an RSS feed from a hash or YAML config.
- `Html2rss.auto_source(url)` discovers selectors and then builds a feed.
- `Html2rss::CLI` exposes `feed` and `auto` commands for end users.

## System Pipeline

Follow the gem’s pipeline exactly; every enhancement must respect these boundaries so responsibilities stay isolated.

1. **Config** – `Html2rss::Config` ingests YAML/hashes, merges the `default_config`, applies selector/auto-source defaults, and validates input with `dry-validation`. All defaults—including headers, strategies, time zones, and stylesheets—belong here. Extend behaviour by updating `Config.default_config`, never by altering downstream services.
2. **Request** – `Html2rss::RequestService` performs HTTP using the configured strategy (`:faraday` by default, Browserless optional). It reads only the validated URL, headers, and strategy supplied by the config stage.
3. **Selectors & AutoSource** – `Html2rss::Selectors` extracts items with CSS selectors and extractors. `Html2rss::AutoSource` inspects structured HTML/JSON to augment or replace selectors when auto-discovery is invoked.
4. **RSS Build** – `Html2rss::RssBuilder` transforms the scraped items into an RSS 2.0 feed, applying channel overrides and optional stylesheets.

Keep logic anchored to the correct stage. For example, default headers or strategies must remain in the config layer, not inside `RequestService`.

## Contributor Entrypoint

- Treat `lib/html2rss.rb` as the contributor-facing entrypoint to the gem.
- A curious contributor should be able to read `lib/html2rss.rb` top to bottom and understand the high-level pipeline:
  config -> request session -> initial response -> article collection -> deduplication -> rendering.
- Keep `lib/html2rss.rb` focused on that orchestration story. It should explain what happens, not how every detail is calculated.
- Low-level setup details belong with their owners:
  - top-level feed config shaping belongs in `Html2rss::Config`
  - request policy and session assembly belong in `Html2rss::RequestSession`
  - extraction details belong in `Html2rss::Selectors` and `Html2rss::AutoSource`
  - rendering details belong in the builders
- Do not let `lib/html2rss.rb` accumulate source-specific heuristics, transport-policy calculations, or other implementation details that distract from the pipeline narrative.
- Prefer a small number of orchestration helpers in `lib/html2rss.rb` with names that describe pipeline phases, not mechanics.

## Coding Standards

- Target Ruby 3.2 or newer.
- Use plain Ruby—never pull in ActiveSupport.
- Add `# frozen_string_literal: true` to every Ruby file.
- Prefer keyword arguments.
- Favor functional iterators (`map`, `filter`, `find`) over imperative loops.
- Keep methods short (≤10 lines) and single-purpose.
- Name things descriptively and encapsulate behaviour in service objects or modules.
- Raise meaningful errors; never fail silently.
- Document every public method with YARD tags (`@param`, `@return`).
- Prefer direct, skimmable code over metric-driven indirection. Do not introduce tiny helper methods whose main purpose is to satisfy RuboCop metrics if they make the main flow harder to read.
- For contributor-facing entrypoints and CLI code, targeted RuboCop disables are acceptable when they preserve a clearer, more direct reading experience than extra abstraction would.

## Testing Standards

- Use RSpec with clear `describe` and `context` blocks.
- Express setup with `let`.
- Do not define methods within \_spec.rb files. If unavoidable, consider creating a supporting file (helper/shared_example/...).
- Never use `send(:method_name)`
- Use of [rspec-matchers](https://rspec.info/features/3-13/rspec-expectations/built-in-matchers/) properly.
- Fix Rubocop offense `RSpec/MultipleExpectations` by taging example with `:aggregate_failures`.
- Prefer `expect(...).to eq(...)` and `expect(...).to have_received(...)` expectations.
- Stub with `allow(...).to receive(...).and_return(...)`.
- Share examples for common extractor or post-processor behaviours.
- Cover happy paths and edge cases.

## Security & Performance

- Sanitize all HTML before output.
- Validate every input; never trust remote data.
- Use `Set` for membership tests.
- Cache expensive work when it is safe to do so.
- Reach for the `parallel` gem when concurrency will help.
- Minimize allocations; prefer bang methods when appropriate.
- Focus on root causes rather than patching symptoms.

## Operating Checklist

- Keep methods small and focused.
- Use `make quick` during implementation for the fast local feedback loop. It should stay focused on changed-file linting and targeted specs.
- Treat `make ready` as the implementation quality gate before handoff or a potential PR merge. It must cover the repo's required merge checks.
- Run Ruby, Bundler, Rake, RuboCop, Reek, YARD, and RSpec commands through `mise exec -- ...` directly or via Make targets.
- Exercise all core flows with tests.
- Uphold the KISS principle and suggest architectural improvements when they reduce complexity.

## Anti-Patterns to Avoid

- Adding Rails or ActiveSupport.
- Hardcoding site-specific logic (move it into configs instead).
- Skipping tests or documentation.
- Ignoring lint or smell warnings.
- Using `eval` or global state.
- Over-engineering or adding unused code (YAGNI).

## Workflow

1. Study existing patterns before you modify or extend them.
2. Implement changes while running `make quick` frequently.
3. Verify with `make ready` before committing or handing work back for review.
4. Commit only after the `make ready` quality gate passes, unless you are explicitly handing off a known-red state.
5. Write commit messages using the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) standard so history stays machine-readable.

## Agent Preferences

- For Ruby implementation, debugging, refactoring, and test work in this repository, use the `ruby-dev` skill when available.
- When improving or reviewing specs, prefer the local Dash MCP docsets for Ruby/RSpec references before reaching elsewhere. In particular, use the local `rspec-expectations`, `rspec-core`, and related docsets to choose more precise built-in matchers and align assertions with actual object contracts.
