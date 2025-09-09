# html2rss – Copilot Instructions

## Purpose

Generate RSS 2.0 feeds from websites by scraping HTML/JSON using CSS selectors or auto-detection.

## Core API

- `Html2rss.feed(config)` → build RSS from config hash/YAML
- `Html2rss.auto_source(url)` → auto-detect and build RSS
- `Html2rss::CLI` → `feed` and `auto` commands

## Architecture

- **Config** – load/validate YAML/hash
- **RequestService** – fetch via Faraday (default) or Browserless
- **Selectors** – extract content via CSS selectors, extractors, post-processors
- **AutoSource** – detect via Schema.org, semantic HTML, patterns
- **RssBuilder** – convert to `Article` objects, render RSS 2.0

## Coding Rules

- Target Ruby 3.2+
- Use plain Ruby, no ActiveSupport
- Add `# frozen_string_literal: true`
- Prefer keyword args
- Favor `map`, `filter`, `find` over loops
- Methods ≤ 10 lines, single responsibility
- Use descriptive names
- Encapsulate logic in service objects/modules
- Raise meaningful errors (never silently fail)
- Add YARD docs (`@param`, `@return`) to all public methods

## Testing Rules

- Use RSpec with `describe` + `context`
- Use `let` for setup
- Prefer `expect(...).to eq(...)` or `expect(...).to have_received(...)`
- Use `allow(...).to receive(...).and_return(...)` for mocking
- Provide shared examples for extractors/post-processors
- Cover both happy paths and edge cases

## Security & Performance

- Sanitize all HTML before output
- Validate inputs
- Never trust external data
- Use `Set` instead of `Array` for lookups
- Cache expensive operations if safe
- Use `parallel` gem when concurrency helps

## Do ✅

- Keep methods small, focused
- Follow RuboCop and Reek
- Write tests for all core flows
- Use service objects for responsibilities

## Don’t ❌

- Don’t add Rails/ActiveSupport
- Don’t hardcode site logic (belongs in configs)
- Don’t skip tests or docs
- Don’t ignore lint warnings
- Don’t use `eval` or globals

## Workflow

1. Read existing patterns
2. Code → run `rubocop` and `reek` often
3. Test → run `COVERAGE=true bundle exec rspec`
4. Commit → ensure tests + lints pass
