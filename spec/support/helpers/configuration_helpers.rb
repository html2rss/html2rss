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

  # Validates that a configuration has the required basic structure
  # @param config [Hash] The configuration to validate
  # @param required_fields [Array<Symbol>] Additional required fields beyond basic structure
  # @return [Boolean] True if the configuration is valid
  # @example
  #   expect(validate_configuration_structure(config)).to be true
  def validate_configuration_structure(config, required_fields = [])
    return false unless valid_basic_config?(config)
    return false unless valid_channel_config?(config[:channel])
    return false unless valid_selectors_config?(config[:selectors])

    # Check additional required fields
    required_fields.all? { |field| config.key?(field) }
  end

  # Validates that a selector configuration has the required structure
  # @param selector_config [Hash] The selector configuration to validate
  # @param required_fields [Array<Symbol>] Required fields for the selector
  # @return [Boolean] True if the selector configuration is valid
  # @example
  #   expect(validate_selector_config(config[:selectors][:title], [:selector])).to be true
  def validate_selector_config(selector_config, required_fields = [:selector])
    return false unless selector_config.is_a?(Hash)

    required_fields.all? { |field| selector_config.key?(field) }
  end

  # Validates that post-processing configuration has the correct structure
  # @param post_process_config [Array] The post-processing configuration array
  # @param required_fields [Array<Symbol>] Required fields for post-processing
  # @return [Boolean] True if the post-processing configuration is valid
  # @example
  #   expect(validate_post_process_config(config[:post_process], [:name])).to be true
  def validate_post_process_config(post_process_config, required_fields = [:name])
    return false unless post_process_config.is_a?(Array)
    return false if post_process_config.empty?

    post_process_config.all? do |processor|
      processor.is_a?(Hash) && required_fields.all? { |field| processor.key?(field) }
    end
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
