# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  class Config
    # Validates the configuration hash using Dry::Validation.
    # The configuration options adhere to the documented schema in README.md.
    class Validator < Dry::Validation::Contract # rubocop:disable Metrics/ClassLength
      # URI format used for channel URL validation.
      URI_REGEXP = Url::URI_REGEXP
      # Allowed stylesheet MIME types.
      STYLESHEET_TYPES = FeedBuilder::Rss::Stylesheet::TYPES
      # Optional language/region format (`en` or `en-US`).
      LANGUAGE_FORMAT_REGEX = /\A[a-z]{2}(-[A-Z]{2})?\z/
      # Baseline strategy-plan enum (:auto plus concrete RequestService strategies).
      BASE_STRATEGY_OPTIONS = Html2rss::FeedPipeline::StrategyPlan.accepted_names.freeze
      # Controlled vocabulary for catalog-only `directory.topics` (not RSS channel fields).
      DIRECTORY_TOPICS = %w[
        sports energy tech science news entertainment jobs finance
        security travel environment consumer civic product research
      ].freeze

      # Contract for the top-level `channel` section.
      ChannelConfig = Dry::Schema.Params do
        required(:url).filled(:string, format?: URI_REGEXP)
        optional(:title).maybe(:string)
        optional(:description).maybe(:string)
        optional(:language).maybe(:string, format?: LANGUAGE_FORMAT_REGEX)
        optional(:ttl).maybe(:integer, gt?: 0)
        optional(:time_zone).maybe(:string)
        optional(:author).maybe(:string)
        optional(:image).maybe(:string, format?: URI_REGEXP)
      end

      # Contract for catalog-only `directory` metadata (topics for feed directories).
      DirectoryConfig = Dry::Schema.Params do
        optional(:topics).value(:array, min_size?: 1).each(:string, included_in?: DIRECTORY_TOPICS)
      end

      # Contract for a stylesheet entry in `stylesheets`.
      StylesheetConfig = Dry::Schema.Params do
        required(:href).filled(:string)
        required(:type).filled(:string, included_in?: STYLESHEET_TYPES)
        optional(:media).maybe(:string)
      end

      # Contract for Botasaurus-specific request options.
      BotasaurusRequestConfig = Dry::Schema.Params do
        config.validate_keys = true

        optional(:execution_mode).filled(:string, included_in?: %w[auto request browser])
        optional(:navigation_mode).filled(:string, included_in?: %w[auto get google_get google_get_bypass organic_get])
        optional(:max_retries).filled(:integer, gteq?: 0, lteq?: 3)
        optional(:wait_for_selector).maybe(:string)
        optional(:wait_timeout_seconds).filled(
          :integer, gt?: 0, lteq?: Html2rss::RequestService::BotasaurusContract::MAX_WAIT_TIMEOUT_SECONDS
        )
        optional(:scroll).filled(:bool)
        optional(:scroll_to_bottom).filled(:bool)
        optional(:block_images).filled(:bool)
        optional(:block_images_and_css).filled(:bool)
        optional(:block_trackers).filled(:bool)
        optional(:wait_for_complete_page_load).filled(:bool)
        optional(:headless).filled(:bool)
        optional(:proxy).filled(:string)
        optional(:user_agent).filled(:string)
        optional(:window_size).value(:array, min_size?: 2, max_size?: 2).each(:integer, gt?: 0)
        optional(:lang).filled(:string)
        optional(:cookies).hash
        optional(:headers).hash
      end

      # Contract for the top-level `request` section.
      RequestConfig = Dry::Schema.Params do
        optional(:max_redirects).filled(:integer, gteq?: 0)
        optional(:max_requests).filled(:integer, gt?: 0)
        optional(:total_timeout_seconds).filled(:integer, gt?: 0)
        optional(:botasaurus).hash(BotasaurusRequestConfig)
        optional(:local_file_path).filled(:string)
      end

      params do
        optional(:strategy).filled(:symbol)
        required(:channel).hash(ChannelConfig)
        optional(:directory).hash(DirectoryConfig)
        optional(:headers).hash
        optional(:stylesheets).array(StylesheetConfig)
        optional(:auto_source).hash(Config::AutoSourceContract)
        optional(:selectors).hash
        optional(:dynamic_params_error).maybe(:string)
        optional(:request).hash(RequestConfig)
      end

      rule(:headers) do
        value&.each do |key, header_value|
          unless header_value.is_a?(String)
            key([:headers, key]).failure("must be a String, but got #{header_value.class}")
          end
        end
      end

      rule(:dynamic_params_error) do
        base.failure(value) if value
      end

      rule(:strategy) do
        next if value.nil?
        next if Html2rss::FeedPipeline::StrategyPlan.valid?(value)

        key.failure("must be one of: #{BASE_STRATEGY_OPTIONS.join(', ')}")
      end

      # Ensure at least one of :selectors or :auto_source is present.
      rule(:selectors, :auto_source) do
        unless values.key?(:selectors) || values.key?(:auto_source)
          base.failure("Configuration must include at least 'selectors' or 'auto_source'")
        end
      end

      rule(:selectors) do
        next unless value

        errors = Config::SelectorsValidator.call(value).errors
        errors.each { |error| key(:selectors).failure(error.text) } unless errors.empty?
      end

      # URL validation delegated to Url class
      rule(:channel) do
        if (url_string = values.dig(:channel, :url)) && !url_string.empty?
          begin
            Html2rss::Url.for_channel(url_string)
          rescue ArgumentError => error
            key(%i[channel url]).failure(error.message)
          end
        end

        if (image_string = values.dig(:channel, :image)) && !image_string.empty?
          begin
            Html2rss::Url.from_absolute(image_string)
          rescue ArgumentError => error
            key(%i[channel image]).failure(error.message)
          end
        end
      end
    end
  end
end
