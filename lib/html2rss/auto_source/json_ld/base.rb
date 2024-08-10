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
        def self.to_article(article, url:)
          new(article, url:).to_article
        end

        def initialize(article, url:)
          @article = article
          @url = url
          @attributes = %i[id title abstract description url image published_at] + specific_attributes
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

        def id = article[:@id] || url&.path || title.to_s.downcase.gsub(/\s+/, '-')
        def title = article[:title]
        alias headline title

        def abstract = article[:abstract]

        def description
          [article[:description], article[:article_body]].max_by { |desc| desc.to_s.size }
        end

        # @return [Adressable::URI, nil] the URL of the article
        def url
          url = article[:url]
          if url.to_s.empty?
            Log.debug("JsonLD#Base.url: no url in article: #{article.inspect}")
            return
          end

          Utils.build_absolute_url_from_relative(url, @url)
        end
        alias link url

        def images = [article[:image]].flatten.compact
        def image = images.first || nil

        def published_at
          if (string = article[:datePublished])
            DateTime.parse(string)
          end
        rescue Date::Error
          Log.warn("JsonLD#Base.published_at: invalid datePublished: #{string.inspect}")
          nil
        end
      end
    end
  end
end
