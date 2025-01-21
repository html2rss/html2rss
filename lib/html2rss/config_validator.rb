# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  ##
  # This class is responsible for validating the configuration hash.
  # The configuration options and their formats are documented in the README.md file.
  class ConfigValidator < Dry::Validation::Contract
    URI_REGEXP = URI::DEFAULT_PARSER.make_regexp
    STYLESHEET_TYPES = RssBuilder::Stylesheet::TYPES
    STRATEGY_NAMES = RequestService.strategy_names.map(&:to_sym).freeze
    LANGUAGE_FORMAT_REGEX = /\A[a-z]{2}(-[A-Z]{2})?\z/

    ChannelConfig = Dry::Schema.Params do
      required(:url).filled(:string, format?: URI_REGEXP)
      optional(:title).filled(:string)
      optional(:description).filled(:string)
      optional(:link).filled(:string, format?: URI_REGEXP)
      optional(:language).filled(:string, format?: LANGUAGE_FORMAT_REGEX)
      optional(:ttl).filled(:integer, gt?: 0)
      optional(:time_zone).filled(:string)
    end

    AutoSourceConfig = Dry::Schema.Params do
      optional(:test).filled(:string)
      # TODO: add real configuration options
    end

    StylesheetConfig = Dry::Schema.Params do
      required(:href).filled(:string)
      optional(:type).filled(:string, included_in?: STYLESHEET_TYPES)
      optional(:media).filled(:string)
    end

    params do
      required(:strategy).filled(:symbol, included_in?: STRATEGY_NAMES)
      optional(:headers).hash
      optional(:stylesheets).array(StylesheetConfig)
      required(:channel).hash(ChannelConfig)
      optional(:auto_source).hash(AutoSourceConfig)
      optional(:selectors).hash
    end

    rule(:headers) do
      value.each_value do |value|
        key.failure('`headers` values must be a String') unless value.is_a?(String)
      end
    end

    rule(:selectors, :auto_source) do
      base.failure('must have at least `selectors` or `auto_source`') if !key?(:selectors) && !key?(:auto_source)
    end

    rule(:selectors) do
      next unless value

      Html2rss::Selectors::Config.call(value).errors.each { |error| key(:selectors).failure(error) }
    end

    ##
    # @param [Hash] config
    # @return [Hash<Symbol, Object>] the validated configuration.
    def self.call(config)
      result = new.call(config)
      return result.to_h if result.success?

      raise ArgumentError,
            "Configuration validation failed: #{result.errors(full: true).messages.join(', ')}"
    end
  end
end
