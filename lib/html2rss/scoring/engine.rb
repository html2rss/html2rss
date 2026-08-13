# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Ranks AutoSource::Segment instances with an explicit feature registry (no send).
    class Engine
      # Maximum segments to extract after ranking (lazy extraction guard).
      TOP_K = 50

      # Quality feature triples: [FeatureId, predicate, weight].
      QUALITY_RULES = [
        [:title_word_count_ge3, ->(o) { o[:title_word_count] >= 3 }, 40],
        [:title_word_count_ge7, ->(o) { o[:title_word_count] >= 7 }, 15],
        [:path_length_gt6, ->(o) { o[:path_length] > 6 }, 20],
        [:content_path, ->(o) { o[:content_path] }, 15],
        [:publish_marker, ->(o) { o[:publish_marker] }, 15],
        [:descriptive_context, ->(o) { o[:descriptive_context] }, 10],
        [:article_container, ->(o) { o[:article_container] }, 10],
        [:content_tokens, ->(o) { o[:content_tokens] }, 10]
      ].freeze

      # Junk feature triples: [FeatureId, predicate, weight].
      JUNK_RULES = [
        [:non_content_utility_path, ->(o) { o[:utility_path] && !o[:content_path] && !o[:strong_post_suffix] }, 25],
        [:utility_prefix_title_short, ->(o) { o[:utility_prefix_title] && o[:title_word_count] <= 6 }, 15],
        [:shallow, ->(o) { o[:shallow] }, 10],
        [:weak_container, ->(o) { !o[:publish_marker] && !o[:descriptive_context] }, 10],
        [:recommended_title_non_content, ->(o) { o[:recommended_title] && !o[:content_path] }, 10],
        [:high_confidence_junk_path, ->(o) { o[:high_confidence_junk_path] }, 5],
        [:junk_tokens, ->(o) { o[:junk_tokens] }, 15]
      ].freeze

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
      # Filters hard-junk but preserves discovery order (used by list/cluster fallback scrapers).
      #
      # @param segments [Array<Html2rss::AutoSource::Segment>]
      # @param limit [Integer]
      # @return [Array<RankedSegment>]
      def select_eligible(segments, limit: TOP_K)
        segments.filter_map { |segment| rank_one(segment) }
                .sort_by(&:position)
                .first(limit)
      end

      ##
      # @param segments [Array<Html2rss::AutoSource::Segment>]
      # @param limit [Integer]
      # @return [Array<RankedSegment>]
      def rank_top(segments, limit: TOP_K)
        rank(segments).first(limit)
      end

      private

      def rank_one(segment) # rubocop:disable Metrics/MethodLength
        facts = segment.primary_link ? @link_resolver.destination_facts(segment.primary_link) : nil
        return if facts&.high_confidence_junk_path && segment.primary_link

        obs = @assessor.call(segment.root_node, segment.primary_link, destination_facts: facts)
        return if hard_junk?(obs)

        quality, quality_parts = apply_rules(QUALITY_RULES, obs)
        junk, junk_parts = apply_rules(JUNK_RULES, obs)
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

      def apply_rules(rules, obs)
        parts = {}
        rules.each do |feature_id, predicate, weight|
          parts[feature_id] = weight if predicate.call(obs)
        end
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
