# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  class Config
    # Validates the configuration hash using Dry::Validation.
    # The configuration options adhere to the documented schema in README.md.
    class Validator < Dry::Validation::Contract
      URI_REGEXP = Url::URI_REGEXP
      STYLESHEET_TYPES = RssBuilder::Stylesheet::TYPES
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

      WaitForNetworkIdleConfig = Dry::Schema.Params do
        optional(:timeout_ms).filled(:integer, gt?: 0)
      end

      BrowserlessPreloadClickSelectorConfig = Dry::Schema.Params do
        required(:selector).filled(:string)
        optional(:max_clicks).filled(:integer, gt?: 0)
        optional(:delay_ms).filled(:integer, gteq?: 0)
        optional(:wait_for_network_idle).hash(WaitForNetworkIdleConfig)
      end

      BrowserlessPreloadScrollConfig = Dry::Schema.Params do
        optional(:iterations).filled(:integer, gt?: 0)
        optional(:delay_ms).filled(:integer, gteq?: 0)
        optional(:wait_for_network_idle).hash(WaitForNetworkIdleConfig)
      end

      BrowserlessPreloadConfig = Dry::Schema.Params do
        optional(:wait_for_network_idle).hash(WaitForNetworkIdleConfig)
        optional(:click_selectors).array(BrowserlessPreloadClickSelectorConfig)
        optional(:scroll_down).hash(BrowserlessPreloadScrollConfig)
      end

      BrowserlessRequestConfig = Dry::Schema.Params do
        optional(:preload).hash(BrowserlessPreloadConfig)
      end

      RequestConfig = Dry::Schema.Params do
        optional(:browserless).hash(BrowserlessRequestConfig)
      end

      params do
        required(:strategy).filled(:symbol)
        required(:channel).hash(ChannelConfig)
        optional(:headers).hash
        optional(:stylesheets).array(StylesheetConfig)
        optional(:auto_source).hash(AutoSource::Config)
        optional(:selectors).hash
        optional(:request).hash(RequestConfig)
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

      # URL validation delegated to Url class
      rule(:channel) do
        next unless values[:channel]&.key?(:url)

        url_string = values[:channel][:url]
        next if url_string.nil? || url_string.empty?

        begin
          Html2rss::Url.for_channel(url_string)
        rescue ArgumentError => error
          key(%i[channel url]).failure(error.message)
        end
      end
    end
  end
end
