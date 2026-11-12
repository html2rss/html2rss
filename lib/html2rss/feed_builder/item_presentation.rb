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
        # The item body: sanitized description text after at most one media element, the RSS enclosure
        # ({.rss_enclosure_for}) when it is audio or video, else the item image ({Html::Rendering::DescriptionBuilder}).
        #
        # @param article [Html2rss::Article]
        # @return [String, nil] sanitized description HTML/text for feed item bodies
        def description_for(article)
          Html::Rendering::DescriptionBuilder.new(
            base: article.description,
            title: article.title,
            url: article.url,
            enclosure: rss_enclosure_for(article),
            image: article.image
          ).call
        end

        ##
        # The one RSS +enclosure+ of an item: its first audio or video file, else its first downloadable
        # document or archive ({Article::Enclosure#document?}: PDF, ZIP). Images stay on the description /
        # JSON Feed; stream playlists, Flash players and watch or player pages ({Article::Enclosure#player_page?})
        # are never one.
        #
        # @param article [Html2rss::Article]
        # @return [Html2rss::Article::Enclosure, nil]
        def rss_enclosure_for(article)
          enclosures = article.enclosures
          enclosures.find(&:media?) || enclosures.find(&:document?)
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
