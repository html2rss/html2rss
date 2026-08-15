# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Ranks AutoSource::Segment instances with an explicit feature registry (no send).
    class Engine
      # Soft cap after score-floor filtering (lazy extraction guard; breadth > blind top-50).
      TOP_K = 99
      # Minimum composite score retained by {#rank_top} (precision floor).
      SCORE_FLOOR = 0.0

      FEATURE_IDS = %i[
        title_word_count_ge3 title_word_count_ge7 path_length_gt6 content_path
        publish_marker descriptive_context article_container content_tokens
        non_content_utility_path utility_prefix_title_short shallow weak_container
        recommended_title_non_content high_confidence_junk_path junk_tokens
        heading_anchor heading_text_match meaningful_text content_like_destination
        cluster_size cluster_avg_words cluster_heading cluster_time cluster_date
      ].to_set.freeze
      private_constant :FEATURE_IDS

      # Quality feature triples: [feature_id, predicate, weight].
      QUALITY_RULES = [
        [:title_word_count_ge3, ->(o) { o.title_word_count >= 3 }, 40],
        [:title_word_count_ge7, ->(o) { o.title_word_count >= 7 }, 15],
        [:path_length_gt6, ->(o) { o.path_length > 6 }, 20],
        [:content_path, lambda(&:content_path), 15],
        [:publish_marker, lambda(&:publish_marker), 15],
        [:descriptive_context, lambda(&:descriptive_context), 10],
        [:article_container, lambda(&:article_container), 10],
        [:content_tokens, lambda(&:content_tokens), 10]
      ].freeze

      # Junk feature triples: [feature_id, predicate, weight].
      JUNK_RULES = [
        [:non_content_utility_path, ->(o) { o.utility_path && !o.content_path && !o.strong_post_suffix }, 25],
        [:utility_prefix_title_short, ->(o) { o.utility_prefix_title && o.title_word_count <= 6 }, 15],
        [:shallow, lambda(&:shallow), 10],
        [:weak_container, ->(o) { !o.publish_marker && !o.descriptive_context }, 10],
        [:recommended_title_non_content, ->(o) { o.recommended_title && !o.content_path }, 10],
        [:high_confidence_junk_path, lambda(&:high_confidence_junk_path), 5],
        [:junk_tokens, lambda(&:junk_tokens), 15]
      ].freeze

      ##
      # @param id [Symbol]
      # @return [Symbol]
      # @raise [ArgumentError] when id is not in the closed set
      def self.assert_feature_id!(id)
        raise ArgumentError, "unknown feature: #{id.inspect}" unless FEATURE_IDS.include?(id)

        id
      end

      (QUALITY_RULES + JUNK_RULES).each { |feature_id, _, _| assert_feature_id!(feature_id) }

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
      # Filters hard-junk but preserves discovery order (list/cluster scrapers).
      #
      # @param segments [Array<Html2rss::AutoSource::Segment>]
      # @param limit [Integer]
      # @return [Array<RankedSegment>]
      def select_eligible(segments, limit: TOP_K)
        segments.filter_map { |segment| rank_one(segment, hard_junk_mode: :lenient) }
                .sort_by(&:position)
                .first(limit)
      end

      ##
      # @param segments [Array<Html2rss::AutoSource::Segment>]
      # @param limit [Integer]
      # @return [Array<RankedSegment>] score-floor filtered, then capped
      def rank_top(segments, limit: TOP_K)
        rank(segments).select { |ranked| ranked.final_score >= SCORE_FLOOR }.first(limit)
      end

      private

      def rank_one(segment, hard_junk_mode: :strict) # rubocop:disable Metrics/MethodLength
        facts = segment.primary_link ? @link_resolver.destination_facts(segment.primary_link) : nil
        obs = @assessor.call(segment.root_node, segment.primary_link, destination_facts: facts)
        return if obs.hard_junk?(mode: hard_junk_mode)

        quality, quality_parts = apply_rules(QUALITY_RULES, obs)
        junk, junk_parts = apply_rules(JUNK_RULES, obs)
        ranked(
          segment:,
          score: build_score(
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

      def build_score(composite:, quality: nil, junk: nil, breakdown: nil)
        raise ArgumentError, 'composite must be Numeric' unless composite.is_a?(Numeric)

        Score.new(
          composite: composite.to_f,
          quality: (quality.nil? ? composite : quality).to_f,
          junk: (junk || 0).to_f,
          breakdown: normalize_breakdown(breakdown)
        )
      end

      def normalize_breakdown(breakdown)
        return Score::EMPTY_BREAKDOWN if breakdown.nil?

        breakdown.transform_keys { |id| self.class.assert_feature_id!(id) }.freeze
      end

      def ranked(segment:, score:)
        raise ArgumentError, 'segment must be AutoSource::Segment' unless segment.is_a?(Html2rss::AutoSource::Segment)
        raise ArgumentError, 'score must be Scoring::Score' unless score.is_a?(Score)

        RankedSegment.new(segment:, score:)
      end
    end
  end
end
