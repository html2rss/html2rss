# frozen_string_literal: true

module Html2rss
  module Registry
    ##
    # Domain catalog entry for a registry-sourced feed config.
    CatalogEntry = Data.define(
      :id,
      :path,
      :directory,
      :channel,
      :parameters,
      :source,
      :registry
    ) do
      ##
      # @param id [String]
      # @param path [String]
      # @param directory [Hash{Symbol => Object}]
      # @param channel [Hash{Symbol => Object}]
      # @param parameters [Hash{Symbol => Object}]
      # @param source [String]
      # @param registry [String, nil]
      def initialize(id:, path:, directory:, channel:, parameters:, source: 'registry', registry: nil) # rubocop:disable Metrics/ParameterLists
        super
      end

      ##
      # @return [Hash{Symbol => Object}]
      def to_h
        super.compact
      end
    end
  end
end
