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
end
