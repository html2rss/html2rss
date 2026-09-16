# frozen_string_literal: true

module Html2rss
  class Selectors
    # A context instance passed to post-processors.
    # When built via {ItemScope#context_for}, +item_scope+ carries the per-item
    # extraction base_url for nested selects (e.g. Template).
    Context = Data.define(:options, :channel, :item_scope) do
      ##
      # @param options [Hash, nil] post-processor options (YAML step)
      # @param channel [Hash, nil] page channel facts (+url+, +time_zone+)
      # @param item_scope [ItemScope, nil]
      # @option options [String] :name post-processor name
      def initialize(options: nil, channel: nil, item_scope: nil)
        super
      end

      ##
      # @return [Object, nil] channel URL for relative resolution / sanitization
      def channel_url = channel&.[](:url)

      ##
      # @return [String, nil] channel time zone for date parsing
      def time_zone = channel&.[](:time_zone)
    end
  end
end
