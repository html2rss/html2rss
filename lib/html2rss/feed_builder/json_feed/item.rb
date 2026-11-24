# frozen_string_literal: true

module Html2rss
  module FeedBuilder
    class JsonFeed
      ##
      # Maps an {Html2rss::Article} to a JSONFeed 1.1 item hash.
      class Item
        ##
        # @param article [Html2rss::Article]
        def initialize(article)
          @article = article
        end

        ##
        # @return [Hash] the JSONFeed-compliant item hash of a renderable article ({ItemPresentation.renderable?})
        def to_h
          item_payload.merge(content_fields).compact
        end

        private

        attr_reader :article

        ##
        # @return [Hash]
        def item_payload
          {
            id: article.guid,
            url: article.url&.to_s,
            title: article.title,
            image: article.image&.to_s,
            date_published: article.published_at&.iso8601,
            authors: author_array,
            tags:,
            attachments:
          }
        end

        ##
        # @return [Array<Hash>, nil]
        def author_array
          return unless (name = article.author)

          [{ name: }]
        end

        ##
        # JSON Feed items must include content_html or content_text.
        # Title is a fallback only when description is absent.
        #
        # @return [Hash]
        def content_fields
          description = ItemPresentation.description_for(article)
          description ? content_for(description) : { content_text: article.title }
        end

        ##
        # @param description [String]
        # @return [Hash]
        def content_for(description)
          html?(description) ? { content_html: description } : { content_text: description }
        end

        ##
        # @param value [String]
        # @return [Boolean]
        def html?(value)
          Nokogiri::HTML.fragment(value).children.any?(&:element?)
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

          enclosures.map { |enc| attachment_hash(enc) }
        end

        ##
        # @param enclosure [Html2rss::Article::Enclosure]
        # @return [Hash]
        def attachment_hash(enclosure)
          size = enclosure.bytes_length

          {
            url: enclosure.url.to_s,
            mime_type: enclosure.type,
            size_in_bytes: (size if size.positive?),
            duration_in_seconds: enclosure.duration
          }.compact
        end
      end
    end
  end
end
