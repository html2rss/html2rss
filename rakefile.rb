# frozen_string_literal: true

require 'rake'
require 'bundler'

begin
  Bundler.setup
  Bundler::GemHelper.install_tasks
rescue StandardError
  raise "You need to install a bundle first. Try 'thor version:use 3.2.13'"
end

require 'rspec'
require 'rspec/core/rake_task'

task default: [:spec]

desc 'Run all examples'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.ruby_opts = %w[-w]
end
