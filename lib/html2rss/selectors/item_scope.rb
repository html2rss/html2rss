# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Per-item extraction scope: owns the article node, page +base_url+, and
    # +time_zone+ for one extraction pass.
    #
    # Distinct from {Context}, which is the post-processor invocation bag (+options+).
    ItemScope = Data.define(:item, :base_url, :scraper, :time_zone) do
      ##
      # Selects an attribute using this scope's item and base_url.
      #
      # @param name [Symbol, String]
      # @return [Object, Array<Object>]
      def select(name) = scraper.select_in_scope(name, self)

      ##
      # Builds a post-processor {Context} carrying this scope for nested selects.
      #
      # @param options [Hash] post-processor options from the selector config
      # @option options [String] :name post-processor name
      # @return [Context]
      def context_for(options:)
        Context.new(options:, channel_url: base_url, time_zone:, item_scope: self)
      end
    end
  end
end
