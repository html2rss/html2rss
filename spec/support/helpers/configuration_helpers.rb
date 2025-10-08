# frozen_string_literal: true

# Configuration and validation helpers for HTML2RSS example specs
module ConfigurationHelpers
  # Loads an example configuration from the spec/examples directory
  # @param config_name [String] The name of the configuration file (without .yml extension)
  # @return [Hash] The loaded configuration hash
  # @example
  #   config = load_example_configuration('combined_scraper_sources')
  def load_example_configuration(config_name)
    config_file = File.join(%w[spec examples], "#{config_name}.yml")
    Html2rss.config_from_yaml_file(config_file)
  end

  private

  def valid_basic_config?(config)
    config.is_a?(Hash)
  end

  def valid_channel_config?(channel)
    channel.is_a?(Hash) &&
      channel[:url].is_a?(String) &&
      channel[:title].is_a?(String)
  end

  def valid_selectors_config?(selectors)
    selectors.is_a?(Hash) &&
      selectors[:items].is_a?(Hash) &&
      selectors[:items][:selector].is_a?(String)
  end
end
