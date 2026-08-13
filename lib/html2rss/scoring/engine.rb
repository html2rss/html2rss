# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Ranks AutoSource::Segment instances with an explicit feature registry (no send).
    class Engine
      # Maximum segments to extract after ranking (lazy extraction guard).
      TOP_K = 50

      QUALITY_WEIGHTS = {
        title_word_count_ge3: 40,
        title_word_count_ge7: 15,
        path_length_gt6: 20,
        content_path: 15,
        publish_marker: 15,
        descriptive_context: 10,
        article_container: 10,
        content_tokens: 10
      }.freeze

      JUNK_WEIGHTS = {
        non_content_utility_path: 25,
        utility_prefix_title_short: 15,
        shallow: 10,
        weak_container: 10,
        recommended_title_non_content: 10,
        high_confidence_junk_path: 5,
        junk_tokens: 15
      }.freeze

      # @param link_resolver [LinkResolver]
      def initialize(link_resolver:)
        @link_resolver = link_resolver
        @assessor = ContainerAssessor.new(text_classifier: link_resolver.text_classifier)
      end

      ##
      # @param segments [Array<Html2rss::AutoSource::Segment>]
      # @return [Array<RankedSegment>] sorted by composite desc, position asc; hard-junk dropped
      def rank(segments)
        segments.filter_map { |segment| rank_one(segment) }
                .sort_by { |ranked| [-ranked.final_score, ranked.position] }
      end

      ##
      # @param segments [Array<Html2rss::AutoSource::Segment>]
      # @param limit [Integer]
      # @return [Array<RankedSegment>]
      def rank_top(segments, limit: TOP_K)
        rank(segments).first(limit)
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def rank_one(segment)
        facts = segment.primary_link ? @link_resolver.destination_facts(segment.primary_link) : nil
        return if facts&.high_confidence_junk_path && segment.primary_link

        obs = @assessor.call(segment.root_node, segment.primary_link, destination_facts: facts)
        return if hard_junk?(obs)

        quality, quality_parts = quality_score(obs)
        junk, junk_parts = junk_score(obs)
        RankedSegment.build(
          segment:,
          score: Score.build(
            composite: quality - junk,
            quality:,
            junk:,
            breakdown: quality_parts.merge(junk_parts)
          )
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      def quality_score(obs)
        parts = {}
        parts[:title_word_count_ge3] = QUALITY_WEIGHTS[:title_word_count_ge3] if obs[:title_word_count] >= 3
        parts[:title_word_count_ge7] = QUALITY_WEIGHTS[:title_word_count_ge7] if obs[:title_word_count] >= 7
        parts[:path_length_gt6] = QUALITY_WEIGHTS[:path_length_gt6] if obs[:path_length] > 6
        parts[:content_path] = QUALITY_WEIGHTS[:content_path] if obs[:content_path]
        parts[:publish_marker] = QUALITY_WEIGHTS[:publish_marker] if obs[:publish_marker]
        parts[:descriptive_context] = QUALITY_WEIGHTS[:descriptive_context] if obs[:descriptive_context]
        parts[:article_container] = QUALITY_WEIGHTS[:article_container] if obs[:article_container]
        parts[:content_tokens] = QUALITY_WEIGHTS[:content_tokens] if obs[:content_tokens]
        [parts.values.sum, parts]
      end

      def junk_score(obs) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        parts = {}
        if obs[:utility_path] && !obs[:content_path] && !obs[:strong_post_suffix]
          parts[:non_content_utility_path] = JUNK_WEIGHTS[:non_content_utility_path]
        end
        if obs[:utility_prefix_title] && obs[:title_word_count] <= 6
          parts[:utility_prefix_title_short] = JUNK_WEIGHTS[:utility_prefix_title_short]
        end
        parts[:shallow] = JUNK_WEIGHTS[:shallow] if obs[:shallow]
        parts[:weak_container] = JUNK_WEIGHTS[:weak_container] if !obs[:publish_marker] && !obs[:descriptive_context]
        if obs[:recommended_title] && !obs[:content_path]
          parts[:recommended_title_non_content] = JUNK_WEIGHTS[:recommended_title_non_content]
        end
        parts[:high_confidence_junk_path] = JUNK_WEIGHTS[:high_confidence_junk_path] if obs[:high_confidence_junk_path]
        parts[:junk_tokens] = JUNK_WEIGHTS[:junk_tokens] if obs[:junk_tokens]
        [parts.values.sum, parts]
      end

      def hard_junk?(obs) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        weak = [obs[:article_container], obs[:publish_marker], obs[:descriptive_context], obs[:content_path]]
               .count(&:itself) < 2

        obs[:high_confidence_junk_path] ||
          (obs[:selected_anchor_present] && obs[:recommended_title] && obs[:shallow] && weak) ||
          (obs[:selected_anchor_present] && obs[:utility_prefix_title] &&
            obs[:high_confidence_utility_destination] && weak)
      end
    end
  end
end
