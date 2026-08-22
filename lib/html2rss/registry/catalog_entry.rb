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
      :parameters
    ) do
      ##
      # Serializes the entry to a plain hash (not the HTTP wire shape).
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          id:,
          path:,
          directory:,
          channel:,
          parameters:
        }
      end
    end
  end
end
