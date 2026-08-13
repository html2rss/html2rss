# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # AutoSource facade over {Html::SstArticleExtractor}.
    class Extractor
      class << self
        ##
        # @param ranked_or_segment [Scoring::RankedSegment, Segment]
        # @param base_url [String, Html2rss::Url]
        # @param scraper [Class, nil]
        # @param fallback_anchorless [Boolean]
        # @return [Html2rss::Article, nil]
        def call(ranked_or_segment, base_url:, scraper: nil, fallback_anchorless: false)
          Html::SstArticleExtractor.call(
            ranked_or_segment,
            base_url:,
            scraper:,
            fallback_anchorless:
          )
        end
      end
    end
  end
end
