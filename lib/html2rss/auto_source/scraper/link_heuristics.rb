# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Shared link-level heuristics used by scraper-local selection and
      # scoring. This keeps normalization and route/text classification
      # consistent without moving scraper policy into higher orchestration.
      class LinkHeuristics # rubocop:disable Metrics/ClassLength
        # Normalized URL plus reusable route-classification facts for one link.
        DestinationFacts = Data.define(
          :url,
          :destination,
          :segments,
          :content_path,
          :utility_path,
          :taxonomy_path,
          :vanity_path,
          :shallow,
          :strong_post_suffix,
          :high_confidence_junk_path,
          :high_confidence_utility_destination
        )

        # Path segments that usually indicate article-like content routes.
        CONTENT_SEGMENTS = %w[
          article articles blog blogs changelog changelogs insight insights
          launch launches news post posts release releases story stories update updates
        ].to_set.freeze
        # Path segments that often indicate navigation, account, taxonomy, or chrome routes.
        UTILITY_SEGMENTS = %w[
          about account archive archives author authors category categories comment comments
          contact feedback help login logout newsletter newsletters notification notifications
          preference preferences profile register search settings share signup subscribe
          tag tags topic topics
          feed feeds comment-feed comments-feed
          recommended
          for-you
          privacy terms cookie cookies
          join member members membership plus premium plans pricing user users
        ].to_set.freeze
        # Path segments that can be discarded confidently unless counterbalanced by post signals.
        HIGH_CONFIDENCE_JUNK_SEGMENTS = %w[
          about account archive archives author authors category categories comment comments
          contact cookie cookies feedback feed feeds help login logout notification notifications
          preference preferences privacy profile register search settings share signup subscribe
          tag tags terms topic topics comment-feed comments-feed user users
        ].to_set.freeze
        # Path segments identifying taxonomy-style listing destinations.
        TAXONOMY_SEGMENTS = %w[
          category categories tag tags topic topics
        ].to_set.freeze
        # Path segments identifying subscription, pricing, or account conversion pages.
        VANITY_SEGMENTS = %w[
          join membership plus premium pricing plans subscribe signup
        ].to_set.freeze
        # Non-article path segments that can still contain legitimate post slugs deeper in the route.
        DEEP_POST_CONTEXT_SEGMENTS = %w[
          category categories privacy press newsroom
        ].to_set.freeze
        # Utility labels that usually indicate collection or subscription links.
        UTILITY_PREFIX_TEXT = /
          \A\s*(
            view\s+all|
            see\s+all|
            all\s+news|
            subscribe|
            newsletter|
            comment\s+feed|
            comments\s+feed|
            join|
            premium|
            plus
          )\b
        /ix
        # Short labels that usually identify non-article navigation links.
        UTILITY_TEXT = /
          \A\s*(
            about|contact|comments?|join|log\s+in|login|member(ship)?|
            plus|premium|pricing|recommended(\s+for\s+you)?|
            see\s+all|share|sign\s+up|signup|subscribe|view\s+all
          )\b
        /ix
        # Labels for recommendation chrome rather than source articles.
        RECOMMENDED_TEXT = /\A\s*recommended(\s+for\s+you)?\b/i
        # Path segment that begins with a year-like publishing marker.
        YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
        # Hyphenated slug shape common to article permalinks.
        POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i

        # @param base_url [String, Html2rss::Url] page URL used to resolve relative hrefs
        def initialize(base_url)
          @base_url = base_url
        end

        # Builds normalized destination facts for an anchor element or href string.
        #
        # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
        # @return [DestinationFacts, nil] normalized destination facts, or nil for blank/invalid URLs
        def destination_facts(anchor_or_href) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          href = href_for(anchor_or_href)
          return unless href

          url = Html2rss::Url.from_relative(href, @base_url)
          segments = url.path_segments
          content_path = content_path?(segments)
          utility_path = utility_path?(segments)
          taxonomy_path = taxonomy_path?(segments)
          vanity_path = vanity_path?(segments)
          shallow = shallow_destination?(segments)
          strong_post_suffix = strong_post_suffix?(segments)
          high_confidence_junk_path = high_confidence_junk_path?(
            segments,
            content_path:,
            taxonomy_path:,
            strong_post_suffix:
          )
          high_confidence_utility_destination = high_confidence_utility_destination?(
            segments,
            content_path:,
            taxonomy_path:,
            strong_post_suffix:,
            shallow:,
            vanity_path:
          )

          DestinationFacts.new(
            url:,
            destination: url.to_s,
            segments:,
            content_path:,
            utility_path:,
            taxonomy_path:,
            vanity_path:,
            shallow:,
            strong_post_suffix:,
            high_confidence_junk_path:,
            high_confidence_utility_destination:
          )
        rescue ArgumentError
          nil
        end

        # @param segments [Array<String>] normalized URL path segments
        # @return [Boolean] true when the route has article-like path evidence
        def content_path?(segments)
          segments.any? do |segment|
            CONTENT_SEGMENTS.include?(segment) || segment.match?(YEARISH_SEGMENT)
          end
        end

        # @param segments [Array<String>] normalized URL path segments
        # @return [Boolean] true when the route includes utility/navigation evidence
        def utility_path?(segments)
          segments.any? { |segment| UTILITY_SEGMENTS.include?(segment) }
        end

        # @param segments [Array<String>] normalized URL path segments
        # @return [Boolean] true when the route points at conversion or account chrome
        def vanity_path?(segments)
          segments.any? { |segment| VANITY_SEGMENTS.include?(segment) }
        end

        # @param segments [Array<String>] normalized URL path segments
        # @return [Boolean] true when the route points at taxonomy/listing chrome
        def taxonomy_path?(segments)
          segments.any? { |segment| TAXONOMY_SEGMENTS.include?(segment) }
        end

        # @param segments [Array<String>] normalized URL path segments
        # @return [Boolean] true when the route is too shallow to strongly indicate an article
        def shallow_destination?(segments)
          segments.size <= 1 || (segments.size == 2 && HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segments.last))
        end

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text matches a utility label
        def utility_text?(text)
          text.to_s.match?(UTILITY_TEXT)
        end

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text begins with a utility label
        def utility_prefix_text?(text)
          text.to_s.match?(UTILITY_PREFIX_TEXT)
        end

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text identifies recommendation chrome
        def recommended_text?(text)
          text.to_s.match?(RECOMMENDED_TEXT)
        end

        private

        def href_for(anchor_or_href)
          href = if anchor_or_href.respond_to?(:[])
                   anchor_or_href['href'].to_s
                 else
                   anchor_or_href.to_s
                 end

          normalized = href.split('#').first.to_s.strip
          normalized unless normalized.empty?
        end

        def high_confidence_junk_path?(segments, content_path:, taxonomy_path:, strong_post_suffix:)
          return false if segments.empty? || content_path || strong_post_suffix

          taxonomy_route?(segments, taxonomy_path) ||
            utility_only_route?(segments) ||
            deep_utility_context_route?(segments) ||
            shallow_high_confidence_route?(segments)
        end

        def high_confidence_utility_destination?( # rubocop:disable Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
          segments,
          content_path:,
          taxonomy_path:,
          strong_post_suffix:,
          shallow:,
          vanity_path:
        )
          return false if segments.empty? || content_path || strong_post_suffix

          vanity_path ||
            taxonomy_route?(segments, taxonomy_path) ||
            utility_only_route?(segments) ||
            deep_utility_context_route?(segments) ||
            (shallow && utility_path?(segments))
        end

        def utility_only_route?(segments)
          return true if segments.all? { |segment| HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segment) }

          leading = segments[0...-1]
          trailing = segments.last
          return false if leading.empty?

          leading.all? { |segment| HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segment) } &&
            HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(trailing)
        end

        def shallow_high_confidence_route?(segments)
          return false unless shallow_destination?(segments)

          segments.any? do |segment|
            HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segment) || VANITY_SEGMENTS.include?(segment)
          end
        end

        def taxonomy_route?(_segments, taxonomy_path)
          taxonomy_path
        end

        def deep_utility_context_route?(segments)
          leading = segments[0...-1]
          return false if leading.empty?

          leading.all? { |segment| HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segment) }
        end

        def strong_post_suffix?(segments)
          return false if segments.empty?

          last_segment = segments.last
          return false if HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(last_segment) || VANITY_SEGMENTS.include?(last_segment)
          return false unless trusted_post_context?(segments[0...-1])

          last_segment.match?(YEARISH_SEGMENT) || last_segment.match?(POST_SLUG_SEGMENT)
        end

        def trusted_post_context?(leading_segments)
          return false if leading_segments.empty?

          content_path?(leading_segments) ||
            leading_segments.any? { |segment| DEEP_POST_CONTEXT_SEGMENTS.include?(segment) }
        end
      end
    end
  end
end
