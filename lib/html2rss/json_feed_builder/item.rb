# frozen_string_literal: true

module Html2rss
  class JsonFeedBuilder
    ##
    # Maps an {Html2rss::RssBuilder::Article} to a JSONFeed 1.1 item hash.
    class Item
      ##
      # @param article [Html2rss::RssBuilder::Article]
      def initialize(article)
        @article = article
      end

      ##
      # @return [Hash] the JSONFeed-compliant item hash
      def to_h
        content = content_fields
        return if content.empty?

        {
          id: article.guid,
          url: article.url&.to_s,
          title: article.title,
          image: article.image&.to_s,
          date_published: article.published_at&.iso8601,
          authors: author_array,
          tags: tags,
          attachments: attachments
        }.merge(content).compact
      end

      private

      attr_reader :article

      ##
      # @return [Array<Hash>, nil]
      def author_array
        return unless (name = article.author)

        [{ name: }]
      end

      ##
      # JSON Feed items must include content_html or content_text.
      # @return [Hash]
      def content_fields
        return { content_html: article.description } if article.description
        return { content_text: article.title } if article.title

        {}
      end

      ##
      # @return [Array<String>, nil]
      def tags
        cats = article.categories
        cats.empty? ? nil : cats
      end

      ##
      # Maps enclosures to JSONFeed attachment objects.
      # @return [Array<Hash>, nil]
      def attachments
        enclosures = article.enclosures
        return nil if enclosures.empty?

        enclosures.map do |enc|
          attachment = { url: enc.url.to_s, mime_type: enc.type }
          attachment[:size_in_bytes] = enc.bits_length if enc.bits_length&.positive?
          attachment.compact
        end
      end
    end
  end
end
