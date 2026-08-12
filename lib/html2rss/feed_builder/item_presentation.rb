# frozen_string_literal: true

module Html2rss
  module FeedBuilder
    ##
    # Presentation rules for rendering an {Html2rss::Article} into feed wire formats.
    #
    # Owns description enrichment ({Html::Rendering::DescriptionBuilder}) and RSS
    # non-image enclosure selection. {Article} keeps raw extracted fields only.
    module ItemPresentation
      class << self
        ##
        # @param article [Html2rss::Article]
        # @return [String, nil] sanitized description HTML/text for feed item bodies
        def description_for(article)
          Html::Rendering::DescriptionBuilder.new(
            base: article.description,
            title: article.title,
            url: article.url,
            enclosures: article.enclosures,
            image: article.image
          ).call
        end

        ##
        # First non-image enclosure for RSS +enclosure+ (images stay on description / JSON Feed).
        #
        # @param article [Html2rss::Article]
        # @return [Html2rss::Article::Enclosure, nil]
        def rss_enclosure_for(article)
          article.enclosures.find { |enc| !image_mime_type?(enc.type) }
        end

        private

        def image_mime_type?(type)
          type.to_s.downcase.start_with?('image/')
        end
      end
    end
  end
end
