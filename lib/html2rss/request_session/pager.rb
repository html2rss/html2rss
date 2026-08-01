# frozen_string_literal: true

require_relative 'pager/base'
require_relative 'pager/rel_next'
require_relative 'pager/custom_selector'
require_relative 'pager/url_template'
require_relative 'pager/offset'
require_relative 'pager/json_cursor'

module Html2rss
  class RequestSession
    ##
    # Factory for building pagination strategy instances.
    module Pager
      # Mapping of strategy symbols to strategy class implementations.
      # @return [Hash{Symbol => Class}]
      STRATEGIES = {
        rel_next: RelNext,
        custom_selector: CustomSelector,
        url_template: UrlTemplate,
        offset: Offset,
        json_cursor: JsonCursor
      }.freeze

      ##
      # Returns a pager instance for the provided configuration.
      #
      # @param config [Hash, Integer, nil] pagination configuration
      # @param session [RequestSession] request session used to execute follow-ups
      # @param initial_response [RequestService::Response] initial page response
      # @return [RequestSession::Pager::Base] pager strategy instance
      def self.for(config, session:, initial_response:)
        normalized_config = normalize_config(config)
        strategy_name = normalized_config.fetch(:strategy, :rel_next).to_sym

        klass = STRATEGIES.fetch(strategy_name) do
          raise ArgumentError, "Unknown pagination strategy: #{strategy_name}"
        end

        klass.new(session:, initial_response:, config: normalized_config)
      end

      ##
      # Normalizes integer, hash, or nil inputs into a strategy config hash.
      #
      # @param config [Hash, Integer, nil]
      # @return [Hash]
      def self.normalize_config(config)
        case config
        when Integer
          { max_pages: config, strategy: :rel_next }
        when Hash
          normalized = config.transform_keys(&:to_sym)
          normalized[:strategy] = (normalized[:strategy] || :rel_next).to_sym
          normalized
        else
          { max_pages: Base::DEFAULT_MAX_PAGES, strategy: :rel_next }
        end
      end
    end
  end
end
