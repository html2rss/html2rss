# frozen_string_literal: true

require 'rss'

module Html2rss
  module FeedBuilder
    ##
    # Builds an RSS Feed by providing channel, articles and stylesheets.
    class Rss
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
          {
            title: article.title,
            description: ItemPresentation.description_for(article),
            author: article.author
          }.each do |attr, value|
            next if value.nil? || value.empty?

            item_maker.public_send(:"#{attr}=", value)
          end

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

      attr_reader :channel, :articles, :generator

      def blank_string?(value)
        !value.is_a?(String) || value.strip.empty?
      end

      def stylesheets
        @stylesheets.map { |style| Stylesheet.new(**style) }
      end

      # rubocop:disable Metrics/AbcSize
      def make_channel(maker)
        channel_maker = maker.channel
        %i[language title description ttl].each do |key|
          channel_maker.public_send(:"#{key}=", channel.public_send(key))
        end

        channel_maker.managingEditor = channel.author if channel.author
        channel_maker.author = channel.author if channel.author
        channel_maker.link = channel.url.to_s
        channel_maker.generator = generator
        channel_maker.updated = channel.last_build_date

        make_image(maker.image) if channel.image
      end
      # rubocop:enable Metrics/AbcSize

      def make_image(image_maker)
        image_maker.url = channel.image.to_s
        image_maker.title = channel.title.to_s
      end

      def make_items(maker)
        articles.each do |article|
          maker.items.new_item { |item_maker| self.class.add_item(article, item_maker) }
        end
      end
    end
  end
end
