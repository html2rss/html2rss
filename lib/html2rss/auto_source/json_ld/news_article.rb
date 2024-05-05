# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    class JsonLd
      ##
      # Subclass for NewsArticle JSON-LD.
      #
      # See: https://schema.org/NewsArticle
      class NewsArticle < Base
        def specific_attributes = %i[article_body]

        def article_body = article[:articleBody]
      end
    end
  end
end
