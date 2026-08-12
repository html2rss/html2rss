# frozen_string_literal: true

module Html2rss
  # Entrypoint and namespace for feed building and formatting (RSS 2.0 / JSON Feed 1.1).
  module FeedBuilder
    # Builds the requested feed type from the channel and article list.
    #
    # @param type [Symbol] :rss or :json_feed
    # @param channel [Html2rss::Channel, Html2rss::Channel::Snapshot]
    # @param articles [Array<Html2rss::Article>]
    # @return [RSS::Rss, Hash] format-compliant representation of the feed
    def self.build(type, channel:, articles:, **)
      case type
      when :rss
        Rss.new(channel:, articles:, **).call
      when :json_feed
        JsonFeed.new(channel:, articles:, **).call
      else
        raise ArgumentError, "Unknown feed type: #{type}"
      end
    end
  end
end
