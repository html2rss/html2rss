# html2rss Development Makefile

.PHONY: help test lint docs clean

help: ## Show available commands
	@echo "Available commands:"
	@echo "  make test    - Run tests"
	@echo "  make lint    - Run linting"
	@echo "  make docs    - Generate documentation"
	@echo "  make clean   - Clean build artifacts"

test: ## Run tests
	bundle exec rspec

lint: ## Run linting
	bundle exec rubocop
	bundle exec reek

docs: ## Generate documentation
	bundle exec yard doc

clean: ## Clean build artifacts
	rm -rf coverage/ doc/ tmp/ html2rss-*.gem .rspec_status
