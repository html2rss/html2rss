# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Per-item extraction environment: owns the article node, page +base_url+, and
    # +time_zone+ for one extraction pass.
    #
    # Distinct from {StepEnv}, which is the post-processor invocation bag (+options+).
    ItemEnv = Data.define(:item, :base_url, :scraper, :time_zone) do
      ##
      # Selects an attribute using this env's item and base_url.
      #
      # @param name [Symbol, String]
      # @return [Object, Array<Object>]
      def select(name) = scraper.select_in_scope(name, self)

      ##
      # Builds a post-processor {StepEnv} carrying this env for nested selects.
      #
      # @param options [Hash] post-processor options from the selector config
      # @option options [String] :name post-processor name
      # @return [StepEnv]
      def context_for(options:)
        StepEnv.new(options:, base_url:, time_zone:, item_env: self)
      end
    end
  end
end
