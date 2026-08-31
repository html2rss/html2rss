# frozen_string_literal: true

module Html2rss
  ##
  # Service that runs schema validation and live feed extraction on a configuration,
  # enforcing minimum item thresholds and capturing sample output.
  module Test
    module_function

    ##
    # Tests a configuration by validating schema and executing live feed extraction.
    #
    # @param config_input [Hash, String] config hash, YAML string, or file path
    # @param feed_name [String, nil] optional feed name for multi-feed files
    # @param min_items [Integer] minimum extracted items required to pass
    # @param params [Hash] optional dynamic feed parameters
    # @param strategy [Symbol, nil] optional strategy override
    # @return [Html2rss::TestResult]
    def call(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      raw_config, validation = resolve_config_and_validate(config_input, feed_name, params:)
      return validation_failure_result(validation.errors.to_h, raw_config) unless validation.success?

      raw_config[:strategy] = strategy.to_sym if strategy
      raw_config[:params] = params if params&.any?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        feed_result = Html2rss.feed_result(raw_config)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        rss = feed_result.to_rss
        item_count = rss.items.size
        sample_items = extract_samples(rss.items)

        channel_title = feed_result.channel_title
        channel_url = raw_config.dig(:channel, :url).to_s
        strategy_used = feed_result.status.selected_strategy || raw_config[:strategy] || :faraday

        TestResult.new(
          success: item_count >= min_items,
          item_count:,
          sample_items:,
          channel_title:,
          channel_url:,
          strategy_used:,
          duration_seconds: duration.round(3),
          validation_errors: nil,
          error_message: item_count < min_items ? "Extracted #{item_count} items (minimum required: #{min_items})" : nil
        )
      rescue StandardError => error
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        execution_failure_result(error, raw_config, duration)
      end
    end

    def resolve_config_and_validate(config_input, feed_name, params:) # rubocop:disable Metrics/MethodLength
      param_arg = params.empty? ? Config::UNSET : params
      if config_input.is_a?(Hash)
        [config_input, Config.validate(config_input, params: param_arg)]
      elsif File.file?(config_input.to_s)
        file = config_input.to_s
        validation = Config.validate_yaml(file, feed_name, params:)
        config = Config.load_yaml(file, feed_name)
        [config, validation]
      else
        # String YAML content
        parsed = Config.from_yaml(config_input.to_s)
        [parsed, Config.validate(parsed, params: param_arg)]
      end
    rescue StandardError => error
      [{}, Struct.new(:success?, :errors).new(false, { parse: [error.message] })]
    end
    private_class_method :resolve_config_and_validate

    def extract_samples(items, limit: 3)
      items.first(limit).map do |item|
        {
          title: item.title.to_s.strip,
          url: (item.respond_to?(:link) ? item.link : item.url).to_s,
          published_at: (item.respond_to?(:pubDate) ? item.pubDate : item.published_at)
        }
      end
    end
    private_class_method :extract_samples

    def validation_failure_result(errors, raw_config) # rubocop:disable Metrics/MethodLength
      TestResult.new(
        success: false,
        item_count: 0,
        sample_items: [],
        channel_title: raw_config.dig(:channel, :title),
        channel_url: raw_config.dig(:channel, :url),
        strategy_used: raw_config[:strategy],
        duration_seconds: 0.0,
        validation_errors: errors,
        error_message: 'Configuration schema validation failed'
      )
    end
    private_class_method :validation_failure_result

    def execution_failure_result(error, raw_config, duration) # rubocop:disable Metrics/MethodLength
      TestResult.new(
        success: false,
        item_count: 0,
        sample_items: [],
        channel_title: raw_config.dig(:channel, :title),
        channel_url: raw_config.dig(:channel, :url),
        strategy_used: raw_config[:strategy],
        duration_seconds: duration.round(3),
        validation_errors: nil,
        error_message: "#{error.class}: #{error.message}"
      )
    end
    private_class_method :execution_failure_result
  end
end
