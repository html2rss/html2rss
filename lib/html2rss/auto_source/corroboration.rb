# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Keep/drop verdict for structured-tier items, checked against the rendered page.
    #
    # Only {Scraper::CORROBORATED_SCRAPERS} items are checked; publisher-declared sources
    # (native feed, CMS REST API, sitemap, oEmbed) are kept as-is. A URL rendered as a
    # content anchor is kept. On a page that can corroborate, a URL rendered only in chrome
    # is +:chrome_only+. A URL rendered nowhere is +:not_on_page+ when the page renders its
    # cohort (at least half the cohort as content anchors, or a cohort too small to tell);
    # an item of a cohort the page mostly does not render (an app shell, an aggregator linking
    # through redirects) is scored with absence counting against it. A peripheral URL (aside,
    # menu landmark), or any URL on a sparse page or without a page ({PageLinks#sparse?}),
    # is decided by a private article-likeness score: +:keep+ or +:unlikely+.
    #
    # A kept item takes the rendered anchor's URL ({#canonical_url}); {Cleanup} applies it.
    #
    # {Cleanup} owns admission and tallies the drop verdicts.
    class Corroboration
      # Article-likeness score at or above which an uncorroborated item is kept.
      LIKELY_SCORE = 2
      # Fewest items in a scraper's cohort before its URL cohesion or render share counts.
      MIN_COHORT_SIZE = 3

      ##
      # @yieldreturn [PageLinks] the page's links; called at most once, on the first checked item
      def initialize(&page_links)
        @page_links_source = page_links
        @cohesion = {}.compare_by_identity
        @rendered = {}.compare_by_identity
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
        when :absent then unrendered(article, cohort)
        else scored(article, cohort)
        end
      end

      ##
      # Whether the page shows an item in its content. Only checked items can fail: one kept by
      # score (rendered in chrome, a peripheral landmark, or nowhere) is not shown. Exempt items
      # (publisher-declared, or read off the page by a heuristic tier) are taken as shown.
      #
      # @param article [Html2rss::Article] admitted item
      # @return [Boolean]
      def shown?(article)
        !Scraper::CORROBORATED_SCRAPERS.include?(article.scraper) || page_links.placement(article.url) == :content
      end

      ##
      # Whether the page is a media page (a podcast or video listing): more than half of the
      # items read off the page ({Scraper::PAGE_SCRAPERS}) and shown in its content ({#shown?})
      # are media items ({Html2rss::Article#media?}). Each article identity is one item: a
      # structured media item and the card that renders it count once.
      #
      # @param articles [Array<Html2rss::Article>] admitted items
      # @return [Boolean]
      def media_page?(articles)
        cards = articles.select { Scraper::PAGE_SCRAPERS.include?(_1.scraper) && shown?(_1) }
                        .uniq { _1.url.article_identity }
        cards.count(&:media?) * 2 > cards.size
      end

      ##
      # A media page's order: its media items first, then the other items, each group in document
      # order (the position of its content anchor), with items the page does not show in its
      # content last in their given order.
      #
      # @param articles [Array<Html2rss::Article>]
      # @return [Array<Html2rss::Article>]
      def page_order(articles)
        articles.partition(&:media?).flat_map do |group|
          placed, unplaced = group.partition { page_links.content_position(_1.url) }
          placed.sort_by { page_links.content_position(_1.url) } + unplaced
        end
      end

      ##
      # The page's own form of a checked item's URL, when it differs only by scheme, tracking
      # params, trailing slash, or fragment from a rendered content anchor.
      #
      # @param article [Html2rss::Article]
      # @return [Html2rss::Url, nil] nil when the item is exempt, not a content anchor, or already canonical
      def canonical_url(article)
        return unless Scraper::CORROBORATED_SCRAPERS.include?(article.scraper)

        canonical = page_links.canonical_url(article.url)
        canonical unless canonical.to_s == article.url.to_s
      end

      private

      # A sparse page cannot show where a URL is missing from, so the score decides there.
      def uncorroborated(reason, article, cohort)
        page_links.sparse? ? scored(article, cohort) : reason
      end

      # Absence is evidence only against a cohort the page renders: a page showing most of a
      # list left the rest out. A page that renders little of the cohort shows the list
      # elsewhere (client-side, through redirects), so there absence only lowers the score.
      def unrendered(article, cohort)
        return uncorroborated(:not_on_page, article, cohort) if page_links.sparse? || rendered?(cohort)

        scored(article, cohort, absent: true)
      end

      def scored(article, cohort, absent: false)
        likely?(article, cohort, absent:) ? :keep : :unlikely
      end

      def page_links
        @page_links ||= @page_links_source.call
      end

      def likely?(article, cohort, absent:)
        score = [article.published_at, article.image, article.description].count(&:itself)
        score += url_shape(article.url)
        score += 1 if cohesive?(cohort)
        score -= 1 if absent
        score >= LIKELY_SCORE
      end

      # +1 for an article-shaped path, -1 for a section root, 0 otherwise. A shallow path
      # ending in a post slug (+/harbor-ferry-route-returns+) is a root-level permalink, not a
      # section root.
      def url_shape(url)
        facts = LinkDestination::DestinationFacts.build(url)
        return 1 if facts.content_path || facts.strong_post_suffix
        return 0 unless facts.shallow

        facts.segments.last&.match?(LinkDestination::PathClassifier::POST_SLUG_SEGMENT) ? 0 : -1
      end

      # A cohort is cohesive when at least half its URLs share one parent path.
      def cohesive?(cohort)
        return false if cohort.size < MIN_COHORT_SIZE

        @cohesion.fetch(cohort) do
          modal = cohort.map { _1.url.path_segments[0...-1] }.tally.values.max
          @cohesion[cohort] = modal * 2 >= cohort.size
        end
      end

      # A cohort is rendered when at least half its URLs are content anchors, or when it is
      # too small for its share to tell a rendered list from an unrendered one.
      def rendered?(cohort)
        return true if cohort.size < MIN_COHORT_SIZE

        @rendered.fetch(cohort) do
          content = cohort.count { page_links.placement(_1.url) == :content }
          @rendered[cohort] = content * 2 >= cohort.size
        end
      end
    end
  end
end
