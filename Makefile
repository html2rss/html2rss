# html2rss Development Makefile

CHANGED_RUBY := $(strip $(shell git status --short -- '*.rb' '*.rake' 'Gemfile' 'Rakefile' 'exe/*' 'spec/*' | awk '{print $$NF}'))
CHANGED_SPECS := $(filter %_spec.rb,$(CHANGED_RUBY))

.PHONY: help lint-changed test-fast test lint schema validate-fixtures docs quick ready clean

help: ## Show available commands
	@echo "Available commands:"
	@echo "  make quick   - Run the fast local feedback loop"
	@echo "  make test    - Run tests"
	@echo "  make lint    - Run linting"
	@echo "  make schema  - Regenerate and verify the config schema"
	@echo "  make validate-fixtures - Validate fixture configs"
	@echo "  make docs    - Generate documentation"
	@echo "  make ready   - Run the local PR readiness checks"
	@echo "  make clean   - Clean build artifacts"

lint-changed: ## Run RuboCop only on changed Ruby files
ifneq ($(CHANGED_RUBY),)
	mise exec -- bundle exec rubocop $(CHANGED_RUBY)
else
	@echo "No changed Ruby files to lint"
endif

test-fast: ## Run focused specs for the local feedback loop
ifneq ($(CHANGED_SPECS),)
	mise exec -- bundle exec rspec $(CHANGED_SPECS)
else
	mise exec -- bundle exec rspec --only-failures
endif

quick: ## Run the fast local feedback loop
	$(MAKE) lint-changed
	$(MAKE) test-fast

test: ## Run tests
	COVERAGE=true mise exec -- bundle exec rspec

lint: ## Run linting
	mise exec -- bundle exec rubocop
	mise exec -- bundle exec reek

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
	$(MAKE) -j 5 lint test schema validate-fixtures docs

clean: ## Clean build artifacts
	rm -rf coverage/ doc/ tmp/ html2rss-*.gem .rspec_status
