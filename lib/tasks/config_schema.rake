# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../html2rss'
require_relative '../../support/development/config_schema'

namespace :config do
  desc 'Generate config JSON schema'
  task :schema do
    schema = Html2rss::Config::Schema.json_schema
    destination = File.expand_path('../../schema/html2rss-config.schema.json', __dir__)

    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, JSON.pretty_generate(schema))

    puts "Generated config schema at #{destination}"
  end
end
