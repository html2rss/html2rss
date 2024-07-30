# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in html2rss.gemspec
gemspec

group :development, :test do
  gem 'byebug'
  gem 'rake'
  gem 'rspec', '~> 3.0'
  gem 'rubocop'
  gem 'rubocop-md'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
  gem 'vcr'
  gem 'yard'
end

group :test do
  gem 'simplecov', require: false
end
