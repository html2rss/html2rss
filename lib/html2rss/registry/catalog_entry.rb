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
