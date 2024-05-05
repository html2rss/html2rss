# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    class JsonLd
      ##
      # Base class for JSON-LD articles.
      #
      # To add more attributes:
      # 1. Create a subclass
      # 2. Override `#specific_attributes`
      # 3. For each specific attribute, define a method that returns the desired value.
      # 4. Add the subclass to JsonLd::ARTICLE_TYPES and JsonLd#parse_article.
      class Base
        def initialize(article)
          @article = article
          @attributes = %i[id headline description url image published_at] + specific_attributes
        end

        attr_reader :article

        # @return [Array<Symbol>] addition attributes for specific type (override in subclass)
        def specific_attributes
          []
        end

        def to_article
          @attributes.to_h do |attribute|
            [attribute, public_send(attribute)]
          end
        end

        def id = article[:@id]
        def headline = article[:headline]
        alias title headline

        def description = article[:description]
        def url = article[:url]
        alias link url

        def images = [article[:image]].flatten.compact
        def image = images.first || nil

        def published_at
          if (string = article[:datePublished])
            DateTime.parse(string)
          end
        rescue Date::Error
          # TODO: log error
          nil
        end

        def self.to_article(article)
          new(article).to_article
        end
      end
    end
  end
end
