# frozen_string_literal: true

module Html2rss
  class Selectors
    # Invocation environment passed to post-processors.
    # When built via {ItemEnv#context_for}, +item_env+ carries the per-item
    # extraction base_url for nested selects (e.g. Template).
    StepEnv = Data.define(:step_config, :base_url, :time_zone, :item_env) do
      ##
      # @param step_config [Hash] post-processor configuration (YAML step)
      # @param base_url [String, Html2rss::Url, nil] page URL for relative resolution
      # @param time_zone [String, nil] channel time zone for date parsing
      # @param item_env [ItemEnv, nil]
      # @option step_config [String] :name post-processor name
      def initialize(step_config: {}.freeze, base_url: nil, time_zone: nil, item_env: nil)
        base_url ||= item_env&.base_url
        time_zone ||= item_env&.time_zone
        super
      end
    end
  end
end
