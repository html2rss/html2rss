# html2rss Development Makefile

SHELL_SCRIPTS = \
	bin/list-changed-paths \
	bin/lint-changed \
	bin/test-fast \
	bin/quick \
	bin/ready \
	bin/setup

.PHONY: help lint-changed test-fast test lint shellcheck schema validate-fixtures docs quick ready clean

help: ## Show available commands
	@echo "Available commands:"
	@echo "  make quick   - Run the fast local feedback loop"
	@echo "  make test    - Run tests"
	@echo "  make lint    - Run linting"
	@echo "  make shellcheck - Run shellcheck on maintained shell scripts"
	@echo "  make schema  - Regenerate and verify the config schema"
	@echo "  make validate-fixtures - Validate fixture configs"
	@echo "  make docs    - Generate documentation"
	@echo "  make ready   - Run the local PR readiness checks"
	@echo "  make clean   - Clean build artifacts"

lint-changed: ## Run RuboCop only on changed Ruby files
	bin/lint-changed

test-fast: ## Run focused specs for the local feedback loop
	bin/test-fast

quick: ## Run the fast local feedback loop
	bin/quick

test: ## Run tests
	COVERAGE=true mise exec -- bundle exec rspec

lint: ## Run linting
	mise exec -- bundle exec rubocop
	mise exec -- bundle exec reek

shellcheck: ## Run shellcheck on maintained shell scripts
	shellcheck $(SHELL_SCRIPTS)

schema: ## Regenerate and verify the config schema
	mise exec -- bundle exec rake config:schema
	git diff --exit-code schema/html2rss-config.schema.json

validate-fixtures: ## Validate fixture configs
	mise exec -- bundle exec exe/html2rss validate spec/fixtures/single.test.yml
	mise exec -- bundle exec exe/html2rss validate spec/fixtures/feeds.test.yml notitle
	! mise exec -- bundle exec exe/html2rss validate spec/fixtures/invalid_selectors.test.yml

docs: ## Generate documentation
	mise exec -- bundle exec yard doc

ready: ## Run the local PR readiness checks
	bin/ready

clean: ## Clean build artifacts
	rm -rf coverage/ doc/ tmp/ html2rss-*.gem .rspec_status
