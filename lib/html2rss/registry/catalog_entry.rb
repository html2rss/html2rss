# frozen_string_literal: true

module Html2rss
  module Registry
    CatalogEntry = Data.define(:id, :path, :directory, :channel, :parameters)

    ##
    # Domain catalog entry for a registry-sourced feed config.
    # Wire fields (+source+, +registry+) are stamped by html2rss-web Index at the API edge.
    class CatalogEntry
      ##
      # @return [Hash{Symbol => Object}]
      def to_h = super.compact
    end
  end
end
