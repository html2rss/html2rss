# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Keep/drop verdict for structured-tier items, checked against the rendered page.
    #
    # Only {Scraper::CORROBORATED_SCRAPERS} items are checked; publisher-declared sources
    # (native feed, CMS REST API, sitemap, oEmbed) are kept as-is. A URL rendered as a
    # content anchor is kept. On a page that can corroborate, a URL rendered only in chrome
    # is +:chrome_only+ and one rendered nowhere is +:not_on_page+. A peripheral URL (aside,
    # menu landmark), or any URL on a sparse page or without a page ({PageLinks#sparse?}),
    # is decided by a private article-likeness score: +:keep+ or +:unlikely+.
    #
    # {Cleanup} owns admission and tallies the drop verdicts.
    class Corroboration
      # Article-likeness score at or above which an uncorroborated item is kept.
      LIKELY_SCORE = 2
      # Fewest items in a scraper's cohort before its URL cohesion counts.
      MIN_COHORT_SIZE = 3

      ##
      # @yieldreturn [PageLinks] the page's links; called at most once, on the first checked item
      def initialize(&page_links)
        @page_links_source = page_links
        @cohesion = {}.compare_by_identity
      end

      ##
      # @param article [Html2rss::Article] item with a URL (Cleanup checks validity first)
      # @param cohort [Array<Html2rss::Article>] the items produced by +article+'s scraper
      # @return [Symbol] +:keep+, +:chrome_only+, +:not_on_page+, or +:unlikely+
      def verdict(article, cohort:)
        return :keep unless Scraper::CORROBORATED_SCRAPERS.include?(article.scraper)

        case page_links.placement(article.url)
        when :content then :keep
        when :chrome then uncorroborated(:chrome_only, article, cohort)
        when :absent then uncorroborated(:not_on_page, article, cohort)
        else scored(article, cohort)
        end
      end

      private

      # A sparse page cannot show where a URL is missing from, so the score decides there.
      def uncorroborated(reason, article, cohort)
        page_links.sparse? ? scored(article, cohort) : reason
      end

      def scored(article, cohort)
        likely?(article, cohort) ? :keep : :unlikely
      end

      def page_links
        @page_links ||= @page_links_source.call
      end

      def likely?(article, cohort)
        score = [article.published_at, article.image, article.description].count(&:itself)
        score += url_shape(article.url)
        score += 1 if cohesive?(cohort)
        score >= LIKELY_SCORE
      end

      # +1 for an article-shaped path, -1 for a section root, 0 otherwise.
      def url_shape(url)
        facts = LinkDestination::DestinationFacts.build(url)
        return 1 if facts.content_path || facts.strong_post_suffix

        facts.shallow ? -1 : 0
      end

      # A cohort is cohesive when at least half its URLs share one parent path.
      def cohesive?(cohort)
        return false if cohort.size < MIN_COHORT_SIZE

        @cohesion.fetch(cohort) do
          modal = cohort.map { _1.url.path_segments[0...-1] }.tally.values.max
          @cohesion[cohort] = modal * 2 >= cohort.size
        end
      end
    end
  end
end
