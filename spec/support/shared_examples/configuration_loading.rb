# frozen_string_literal: true

# Shared examples for configuration loading patterns
# These examples provide common patterns for loading and validating configurations

RSpec.shared_examples 'loads configuration from YAML' do |config_name|
  let(:config_file) { File.join(%w[spec examples], "#{config_name}.yml") }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  it_behaves_like 'validates configuration structure'
end

RSpec.shared_examples 'loads configuration with HTML fixture' do |config_name|
  let(:config_file) { File.join(%w[spec examples], "#{config_name}.yml") }
  let(:html_file) { File.join(%w[spec examples], "#{config_name}.html") }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  it_behaves_like 'validates configuration structure'
end

RSpec.shared_examples 'loads configuration with JSON fixture' do |config_name|
  let(:config_file) { File.join(%w[spec examples], "#{config_name}.yml") }
  let(:json_file) { File.join(%w[spec examples], "#{config_name}.json") }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  it_behaves_like 'validates configuration structure'
end
