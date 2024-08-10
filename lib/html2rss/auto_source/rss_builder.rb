# frozen_string_literal: true

require 'rss'

module Html2rss
  class AutoSource
    ##
    # Converts the autosourced channel and articles to an RSS feed.
    class RssBuilder
      def initialize(channel:, articles:, url:)
        @channel = channel
        @articles = articles
        @url = url
      end

      def call
        # TODO: re-use the existing Html2Rss::RssBuilder, ..Item, ..Channel?
        RSS::Maker.make('2.0') do |maker|
          make_channel(maker.channel)
          make_items(maker)
        end
      end

      private

      attr_reader :channel, :articles, :url

      def make_channel(maker)
        maker.language = channel[:language]
        maker.title = channel[:title]
        maker.link = channel[:url]
        maker.description = channel[:description]
        maker.generator = "html2rss [autosourced] V. #{::Html2rss::VERSION}"
      end

      def make_items(maker)
        articles.each do |article|
          maker.items.new_item do |item_maker|
            add_guid(article, item_maker)
            add_image(article, item_maker)

            item_maker.title = article[:title]
            item_maker.description = article[:description]
            item_maker.pubDate = article[:published_at]
            item_maker.link = clean_url(article[:url])
          end
        end
      end

      def clean_url(url)
        link = Html2rss::Utils.build_absolute_url_from_relative(url, @url)
        Html2rss::Utils.sanitize_url(link)
      end

      def add_guid(article, maker)
        maker.guid.tap do |guid|
          guid.content = article.guid
          guid.isPermaLink = false
        end
      end

      def add_image(article, maker)
        return unless article[:image]

        url = clean_url(article[:image])
        return if url.start_with?('data:image/svg+xml')

        maker.enclosure.tap do |enclosure|
          enclosure.url = url
          enclosure.type = Html2rss::Utils.guess_content_type_from_url(article[:image])
          enclosure.length = 0
        end
      end
    end
  end
end
