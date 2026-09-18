# frozen_string_literal: true

module Html2rss
  class Selectors
    # Invocation environment passed to post-processors.
    # When built via {ItemEnv#context_for}, +item_env+ carries the per-item
    # extraction base_url for nested selects (e.g. Template).
    StepEnv = Data.define(:options, :base_url, :time_zone, :item_env) do
      ##
      # @param options [Hash, nil] post-processor options (YAML step)
      # @param base_url [String, Html2rss::Url, nil] page URL for relative resolution
      # @param time_zone [String, nil] channel time zone for date parsing
      # @param item_env [ItemEnv, nil]
      # @option options [String] :name post-processor name
      def initialize(options: nil, base_url: nil, time_zone: nil, item_env: nil)
        super
      end
    end
  end
end
