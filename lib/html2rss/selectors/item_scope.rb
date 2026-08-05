# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Per-item extraction scope: owns the article node and page +base_url+ for one
    # extraction pass. Channel hashes are injected (and cached) by {Selectors}.
    #
    # Distinct from {Context}, which is the post-processor invocation bag (+options+).
    ItemScope = Data.define(:item, :base_url, :scraper, :channel, :post_process_config) do
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
        Context.new(options:, item:, config: post_process_config, scraper:, item_scope: self)
      end
    end
  end
end
