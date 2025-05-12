# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  class Config
    # Validates the configuration hash using Dry::Validation.
    # The configuration options adhere to the documented schema in README.md.
    class Validator < Dry::Validation::Contract
      URI_REGEXP = URI::DEFAULT_PARSER.make_regexp
      STYLESHEET_TYPES = RssBuilder::Stylesheet::TYPES
      STRATEGY_NAMES = RequestService.strategy_names.map(&:to_sym).freeze
      LANGUAGE_FORMAT_REGEX = /\A[a-z]{2}(-[A-Z]{2})?\z/

      ChannelConfig = Dry::Schema.Params do
        required(:url).filled(:string, format?: URI_REGEXP)
        optional(:title).maybe(:string)
        optional(:description).maybe(:string)
        optional(:language).maybe(:string, format?: LANGUAGE_FORMAT_REGEX)
        optional(:ttl).maybe(:integer, gt?: 0)
        optional(:time_zone).maybe(:string)
      end

      StylesheetConfig = Dry::Schema.Params do
        required(:href).filled(:string)
        required(:type).filled(:string, included_in?: STYLESHEET_TYPES)
        optional(:media).maybe(:string)
      end

      params do
        required(:strategy).filled(:symbol, included_in?: STRATEGY_NAMES)
        required(:channel).hash(ChannelConfig)
        optional(:headers).hash
        optional(:stylesheets).array(StylesheetConfig)
        optional(:auto_source).hash(AutoSource::Config)
        optional(:selectors).hash
      end

      rule(:headers) do
        value&.each do |key, header_value|
          unless header_value.is_a?(String)
            key([:headers, key]).failure("must be a String, but got #{header_value.class}")
          end
        end
      end

      # Ensure at least one of :selectors or :auto_source is present.
      rule(:selectors, :auto_source) do
        unless values.key?(:selectors) || values.key?(:auto_source)
          base.failure("Configuration must include at least 'selectors' or 'auto_source'")
        end
      end

      rule(:selectors) do
        next unless value

        errors = Html2rss::Selectors::Config.call(value).errors
        errors.each { |error| key(:selectors).failure(error) } unless errors.empty?
      end
    end
  end
end
