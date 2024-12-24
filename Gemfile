# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in html2rss.gemspec
gemspec

group :development, :test do
  gem 'byebug'
  gem 'rake', require: false
  gem 'yard', require: false

  gem 'reek', require: false

  gem 'rubocop', require: false
  gem 'rubocop-md', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-thread_safety', require: false

  gem 'rspec', '~> 3.0', require: false
  gem 'rspec-instafail', require: false
  gem 'vcr', require: false

  gem 'guard', require: false
  gem 'guard-reek', require: false
  gem 'guard-rspec', require: false
  gem 'guard-rubocop', require: false
end

group :test do
  gem 'climate_control', require: false
  gem 'simplecov', require: false
end
