# frozen_string_literal: true

require 'bundler'
require 'rake'
require 'rspec'
require 'rspec/core/rake_task'

Bundler.setup
Bundler::GemHelper.install_tasks

task default: [:spec]

desc 'Run all examples'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.ruby_opts = %w[-w]
end
