# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Shared link-level heuristics used by scraper-local selection and
      # scoring. This keeps normalization and route/text classification
      # consistent without moving scraper policy into higher orchestration.
      class LinkHeuristics # rubocop:disable Metrics/ClassLength
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

        CONTENT_SEGMENTS = %w[
          article articles blog blogs changelog changelogs insight insights
          launch launches news post posts release releases story stories update updates
        ].to_set.freeze
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
        HIGH_CONFIDENCE_JUNK_SEGMENTS = %w[
          about account archive archives author authors category categories comment comments
          contact cookie cookies feedback feed feeds help login logout notification notifications
          preference preferences privacy profile register search settings share signup subscribe
          tag tags terms topic topics comment-feed comments-feed user users
        ].to_set.freeze
        TAXONOMY_SEGMENTS = %w[
          category categories tag tags topic topics
        ].to_set.freeze
        VANITY_SEGMENTS = %w[
          join membership plus premium pricing plans subscribe signup
        ].to_set.freeze
        DEEP_POST_CONTEXT_SEGMENTS = %w[
          category categories privacy press newsroom
        ].to_set.freeze
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
        UTILITY_TEXT = /
          \A\s*(
            about|contact|comments?|join|log\s+in|login|member(ship)?|
            plus|premium|pricing|recommended(\s+for\s+you)?|
            see\s+all|share|sign\s+up|signup|subscribe|view\s+all
          )\b
        /ix
        RECOMMENDED_TEXT = /\A\s*recommended(\s+for\s+you)?\b/i
        YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
        POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i

        def initialize(base_url)
          @base_url = base_url
        end

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

        def content_path?(segments)
          segments.any? do |segment|
            CONTENT_SEGMENTS.include?(segment) || segment.match?(YEARISH_SEGMENT)
          end
        end

        def utility_path?(segments)
          segments.any? { |segment| UTILITY_SEGMENTS.include?(segment) }
        end

        def vanity_path?(segments)
          segments.any? { |segment| VANITY_SEGMENTS.include?(segment) }
        end

        def taxonomy_path?(segments)
          segments.any? { |segment| TAXONOMY_SEGMENTS.include?(segment) }
        end

        def shallow_destination?(segments)
          segments.size <= 1 || (segments.size == 2 && HIGH_CONFIDENCE_JUNK_SEGMENTS.include?(segments.last))
        end

        def utility_text?(text)
          text.to_s.match?(UTILITY_TEXT)
        end

        def utility_prefix_text?(text)
          text.to_s.match?(UTILITY_PREFIX_TEXT)
        end

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
