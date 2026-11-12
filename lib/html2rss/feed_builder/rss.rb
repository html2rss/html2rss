# frozen_string_literal: true

require 'rss'

module Html2rss
  module FeedBuilder
    ##
    # Builds an RSS Feed by providing channel, articles and stylesheets.
    #
    # A media feed ({ItemPresentation.media_feed?}) also gets the podcast tags clients play from:
    # channel +itunes:image+ and +itunes:author+, item +itunes:duration+ (+HH:MM:SS+) and
    # +itunes:image+, each only when known. It never invents +itunes:explicit+ or a category.
    class Rss
      # First duration in seconds that +itunes:duration+ cannot spell as +HH:MM:SS+ (100 hours).
      MAX_CLOCK_DURATION = 100 * 3600

      class << self
        # @param article [Html2rss::Article] source article
        # @param item_maker [RSS::Maker::RSS20::ItemsBase::ItemBase] RSS item builder
        # @return [void]
        def add_item(article, item_maker)
          add_item_string_values(article, item_maker)
          add_item_categories(article, item_maker)
          add_enclosure(ItemPresentation.rss_enclosure_for(article), item_maker)
          add_item_guid(article, item_maker)
        end

        # @param enclosure [Html2rss::Article::Enclosure, nil] built enclosure object for the current RSS item
        # @param maker [RSS::Maker::RSS20::ItemsBase::ItemBase] RSS item builder
        # @return [void]
        def add_enclosure(enclosure, maker)
          return unless enclosure

          maker.enclosure.tap do |enclosure_maker|
            enclosure_maker.url = enclosure.url.to_s
            enclosure_maker.type = enclosure.type
            enclosure_maker.length = enclosure.bytes_length
          end
        end

        private

        def add_item_string_values(article, item_maker)
          item_maker.title = article.title
          item_maker.author = article.author
          description = ItemPresentation.description_for(article)
          item_maker.description = description if description
          item_maker.link = article.url.to_s if article.url
          item_maker.pubDate = article.published_at&.rfc2822
        end

        def add_item_categories(article, item_maker)
          article.categories.each { |category| item_maker.categories.new_category.content = category }
        end

        def add_item_guid(article, item_maker)
          item_maker.guid.tap do |guid|
            guid.content = article.guid
            guid.isPermaLink = false
          end
        end
      end

      ##
      # @param channel [Html2rss::Channel] The channel information for the RSS feed.
      # @param articles [Array<Html2rss::Article>] The list of articles to include in the RSS feed.
      # @param stylesheets [Array<Hash>] An optional array of stylesheet configurations.
      # @param generator [String] required preformatted generator comment (from {Status})
      def initialize(channel:, articles:, generator:, stylesheets: [])
        raise ArgumentError, 'generator must be a non-blank String' if blank_string?(generator)

        @channel = channel
        @articles = articles
        @stylesheets = stylesheets
        @generator = generator
        @media_feed = ItemPresentation.media_feed?(articles)
      end

      # @return [RSS::Rss] RSS 2.0 document instance
      def call
        RSS::Maker.make('2.0') do |maker|
          Stylesheet.add(maker, stylesheets)

          make_channel(maker)
          make_items(maker)
        end
      end

      private

      attr_reader :channel, :articles, :generator, :media_feed

      def blank_string?(value)
        !value.is_a?(String) || value.strip.empty?
      end

      def stylesheets
        @stylesheets.map { |style| Stylesheet.new(**style) }
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
      def make_channel(maker)
        channel_maker = maker.channel
        channel_maker.language = channel.language
        channel_maker.title = channel.title
        channel_maker.description = channel.description
        channel_maker.ttl = channel.ttl

        channel_maker.managingEditor = channel.author if channel.author
        channel_maker.author = channel.author if channel.author
        channel_maker.link = channel.url.to_s
        channel_maker.generator = generator
        channel_maker.updated = channel.last_build_date

        make_image(maker.image) if channel.image
        make_podcast_channel(channel_maker) if media_feed
      end

      def make_podcast_channel(channel_maker)
        channel_maker.itunes_image = channel.image
        channel_maker.itunes_author = channel.author
      end

      def make_image(image_maker)
        image_maker.url = channel.image.to_s
        image_maker.title = channel.title.to_s
      end

      def make_items(maker)
        articles.each do |article|
          maker.items.new_item do |item_maker|
            self.class.add_item(article, item_maker)
            make_podcast_item(article, item_maker) if media_feed
          end
        end
      end

      def make_podcast_item(article, item_maker)
        duration = ItemPresentation.rss_enclosure_for(article)&.duration
        item_maker.itunes_duration = format_duration(duration) if duration
        item_maker.itunes_image = article.image
      end

      # +HH:MM:SS+; plain seconds from 100 hours on, which +HH+ cannot spell.
      def format_duration(seconds)
        return seconds.to_s if seconds >= MAX_CLOCK_DURATION

        format('%<hours>02d:%<minutes>02d:%<seconds>02d',
               hours: seconds / 3600, minutes: seconds % 3600 / 60, seconds: seconds % 60)
      end
    end
  end
end
