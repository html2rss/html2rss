# frozen_string_literal: true

require 'bundler'
require 'rake'
require 'rspec'
require 'rspec/core/rake_task'

Bundler.setup
Bundler::GemHelper.install_tasks

begin
  require 'rb_sys/extensiontask'

  GEMSPEC = Gem::Specification.load(File.expand_path('html2rss.gemspec', __dir__))

  RbSys::ExtensionTask.new('html2rss_parser', GEMSPEC) do |ext|
    ext.lib_dir = 'lib/html2rss'
  end
rescue LoadError
  # Optional: rb_sys is a development dependency for the Rust HTML experiment.
  desc 'Compile html2rss_parser (requires rb_sys + Rust toolchain)'
  task :compile do
    abort 'rb_sys is not installed; add it via Bundler and retry'
  end
end

task default: [:spec]

desc 'Run all examples'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.ruby_opts = %w[-w]
end

Dir.glob('**/*.rake', base: 'lib/tasks').each { |file| import File.join('lib/tasks', file) }
