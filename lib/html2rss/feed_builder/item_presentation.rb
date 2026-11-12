# frozen_string_literal: true

module Html2rss
  module FeedBuilder
    ##
    # Presentation rules for rendering an {Html2rss::Article} into feed wire formats.
    #
    # Owns description enrichment ({Html::Rendering::DescriptionBuilder}), RSS enclosure
    # choice and the media-feed rule. {Article} keeps raw extracted fields only; media-file
    # facts live on {Article::Enclosure}.
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
        # The one RSS +enclosure+ of an item: its first audio or video file, else its first other
        # file (PDF, archive). Images stay on the description / JSON Feed, and web pages
        # (+text/html+ embed players) are never an enclosure.
        #
        # @param article [Html2rss::Article]
        # @return [Html2rss::Article::Enclosure, nil]
        def rss_enclosure_for(article)
          enclosures = article.enclosures
          enclosures.find(&:media?) || enclosures.find { |enc| !enc.image? && !enc.page? }
        end

        ##
        # A media feed (podcast) is one where more than half of the items carry an audio or video
        # RSS enclosure; only such a feed gets podcast (+itunes:+) tags.
        #
        # @param articles [Array<Html2rss::Article>]
        # @return [Boolean]
        def media_feed?(articles)
          media_items = articles.count { |article| article.enclosures.any?(&:media?) }
          media_items * 2 > articles.size
        end
      end
    end
  end
end
