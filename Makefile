# html2rss Development Makefile

RUBY_RUNNER = $(shell if command -v mise >/dev/null 2>&1; then printf 'mise exec -- '; fi)
SHELL_SCRIPTS = \
	bin/list-changed-paths \
	bin/lint-changed \
	bin/test-fast \
	bin/quick \
	bin/ready \
	bin/setup

.PHONY: help lint-changed test-fast test lint lint-yard shellcheck schema validate-fixtures docs quick ready clean perf-baseline perf-baseline-selectors perf-baseline-feed perf-check corpus-baseline compare-revisions mutant-test mutant

help: ## Show available commands
	@echo "Available commands:"
	@echo "  make quick   - Run the fast local feedback loop"
	@echo "  make test    - Run tests"
	@echo "  make lint    - Run linting"
	@echo "  make lint-yard - Run YARD linting on lib/"
	@echo "  make shellcheck - Run shellcheck on maintained shell scripts"
	@echo "  make schema  - Regenerate and verify the config schema"
	@echo "  make validate-fixtures - Validate fixture configs"
	@echo "  make docs    - Generate documentation"
	@echo "  make perf-baseline - Record auto-source wall/alloc baseline"
	@echo "  make perf-baseline-selectors - Record selectors wall/alloc baseline"
	@echo "  make perf-baseline-feed - Record feed-building wall/alloc baseline"
	@echo "  make perf-check- Gate allocations against the recorded budgets"
	@echo "  make corpus-baseline - Re-record the auto-source corpus ratchet baseline"
	@echo "  make compare-revisions BASE=<rev> HEAD=<rev> PAGES=<dir> [LIMIT=<n>] - Compare auto-source on saved pages"
	@echo "  make ready   - Run the local PR readiness checks"
	@echo "  make mutant-test - Run the suite through mutant's test runner"
	@echo "  make mutant  - Run mutation analysis for SUBJECT"
	@echo "  make clean   - Clean build artifacts"

lint-changed: ## Run RuboCop only on changed Ruby files
	bin/lint-changed

test-fast: ## Run focused specs for the local feedback loop
	bin/test-fast

quick: ## Run the fast local feedback loop
	bin/quick

test: ## Run tests
	COVERAGE=true $(RUBY_RUNNER)bundle exec rspec

lint: ## Run linting
	bin/rubocop

lint-reek:
	$(RUBY_RUNNER)bundle exec reek

lint-yard: ## Run YARD linting on lib/
	$(RUBY_RUNNER)bundle exec yard-lint lib/

shellcheck: ## Run shellcheck on maintained shell scripts
	shellcheck $(SHELL_SCRIPTS)

schema: ## Regenerate and verify the config schema
	$(RUBY_RUNNER)bundle exec rake config:schema
	git diff --exit-code schema/html2rss-config.schema.json

validate-fixtures: ## Validate fixture configs
	$(RUBY_RUNNER)bundle exec exe/html2rss validate spec/fixtures/single.test.yml
	$(RUBY_RUNNER)bundle exec exe/html2rss validate spec/fixtures/feeds.test.yml notitle
	! $(RUBY_RUNNER)bundle exec exe/html2rss validate spec/fixtures/invalid_selectors.test.yml

docs: ## Generate documentation
	$(RUBY_RUNNER)bundle exec yard doc

perf-baseline: ## Record auto-source wall/alloc baseline markdown
	$(RUBY_RUNNER)bin/heuristic-perf-baseline --write spec/perf/baseline-auto-source.md

perf-baseline-selectors: ## Record selectors wall/alloc baseline markdown
	$(RUBY_RUNNER)bin/selectors-perf-baseline --write spec/perf/baseline-selectors.md

perf-baseline-feed: ## Record feed-building (native parse, RSS/JSON Feed render, descriptions) wall/alloc baseline markdown
	$(RUBY_RUNNER)bin/feed-perf-baseline --write spec/perf/baseline-feed.md

perf-check: ## Fail when allocations exceed the recorded budgets (wall time is advisory)
	$(RUBY_RUNNER)bin/heuristic-perf-baseline --check spec/perf/baseline-auto-source.md > /dev/null
	$(RUBY_RUNNER)bin/selectors-perf-baseline --check spec/perf/baseline-selectors.md > /dev/null
	$(RUBY_RUNNER)bin/feed-perf-baseline --check spec/perf/baseline-feed.md > /dev/null

corpus-baseline: ## Re-record the auto-source corpus ratchet baseline
	$(RUBY_RUNNER)bin/auto-source-corpus --write-baseline

compare-revisions: ## Compare auto-source on saved pages across two revisions (BASE, HEAD, PAGES, optional LIMIT)
	$(RUBY_RUNNER)bin/compare-revisions $(BASE) $(HEAD) --pages $(PAGES) $(if $(LIMIT),--limit $(LIMIT))

ready: ## Run the local PR readiness checks
	bin/ready

mutant-test: ## Run the suite through mutant's test runner
	$(RUBY_RUNNER)bundle exec mutant test --usage opensource

mutant: ## Run mutation analysis for SUBJECT
	MUTANT_JOBS=$${MUTANT_JOBS:-2} $(RUBY_RUNNER)bundle exec mutant run --usage opensource $(SUBJECT)

clean: ## Clean build artifacts
	rm -rf coverage/ doc/ docs/ tmp/ html2rss-*.gem .rspec_status
