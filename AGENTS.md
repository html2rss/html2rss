# Repository Agent Instructions

This repository uses `.github/copilot-instructions.md` as the canonical set of agent guidelines.

- Read and follow the instructions defined in `.github/copilot-instructions.md` for all work within this repository.
- Run Ruby, Bundler, Rake, RuboCop, Reek, and RSpec commands through `mise exec -- ...`.
- When fixing test failures, bootstrap the environment first so `mise exec -- bundle exec rspec` runs examples before debugging spec failures.
- When process or decision updates are required, extend `.github/copilot-instructions.md`; this file should remain the primary location for evolving guidance.
