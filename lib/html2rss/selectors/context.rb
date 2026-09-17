# frozen_string_literal: true

module Html2rss
  class Selectors
    # A context instance passed to post-processors.
    # When built via {ItemScope#context_for}, +item_scope+ carries the per-item
    # extraction base_url for nested selects (e.g. Template).
    Context = Data.define(:options, :channel_url, :time_zone, :item_scope) do
      ##
      # @param options [Hash, nil] post-processor options (YAML step)
      # @param channel_url [String, Html2rss::Url, nil] page URL for relative resolution
      # @param time_zone [String, nil] channel time zone for date parsing
      # @param item_scope [ItemScope, nil]
      # @option options [String] :name post-processor name
      def initialize(options: nil, channel_url: nil, time_zone: nil, item_scope: nil)
        super
      end
    end
  end
end
