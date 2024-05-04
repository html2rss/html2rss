# frozen_string_literal: true

require 'rss'

module Html2rss
  class AutoSource
    ##
    # Converts the autosourced channel and articles to a RSS feed.
    class RssBuilder
      def initialize(channel:, articles:, url:)
        @channel = channel
        @articles = articles
        @url = url
      end

      def call
        # TODO: re-use the existing Html2Rss::RssBuilder, ..Item, ..Channel?
        RSS::Maker.make('2.0') do |maker|
          make_channel(channel, maker.channel)
          make_items(articles, maker)
        end
      end

      def make_channel(channel, maker)
        maker.language = channel[:language]
        maker.title = channel[:title]
        maker.link = channel[:url]
        maker.description = channel[:description]
        maker.generator = "html2rss [autosourced] V. #{::Html2rss::VERSION}"
      end

      def make_items(articles, maker)
        articles.each do |article|
          maker.items.new_item do |item|
            item.id = article[:id]
            item.title = article[:headline]
            item.description = article[:description]
            item.link = Html2rss::Utils.build_absolute_url_from_relative(article[:link], url)
          end
        end
      end

      private

      attr_reader :channel, :articles, :url
    end
  end
end
