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

      private

      def clean_url(url)
        link = Html2rss::Utils.build_absolute_url_from_relative(url, @url)
        Html2rss::Utils.sanitize_url(link)
      end

      def add_guid(article, maker)
        guid = maker.guid
        guid.content = generate_guid(article)
        guid.isPermaLink = false
      end

      def generate_guid(article)
        Digest::SHA1.hexdigest [url, article[:id] || article[:url].gsub(url, '')].join('|')
      end

      def add_image(article, maker)
        return unless article[:image]

        maker.enclosure.url = clean_url(article[:image])
        maker.enclosure.type = Html2rss::Utils.guess_content_type_from_url(article[:image])
        maker.enclosure.length = 0
      end

      attr_reader :channel, :articles, :url
    end
  end
end
