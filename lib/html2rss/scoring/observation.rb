# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Typed container signals produced by {ContainerAssessor} for {Engine} rules.
    Observation = Data.define(
      :title_word_count,
      :path_length,
      :content_path,
      :publish_marker,
      :descriptive_context,
      :article_container,
      :content_tokens,
      :junk_tokens,
      :utility_prefix_title,
      :recommended_title,
      :utility_path,
      :strong_post_suffix,
      :shallow,
      :high_confidence_junk_path,
      :high_confidence_utility_destination,
      :selected_anchor_present
    ) do
      ##
      # @return [Boolean] true when fewer than two positive content signals are present
      def weak_signals?
        [article_container, publish_marker, descriptive_context, content_path].count(&:itself) < 2
      end

      ##
      # @param mode [Symbol] +:strict+ for rank/rank_top; +:lenient+ for select_eligible
      # @return [Boolean] true when the observation should be dropped before ranking
      def hard_junk?(mode: :strict)
        case mode
        when :strict
          high_confidence_junk_path || chrome_title_junk?
        when :lenient
          (high_confidence_junk_path && weak_signals?) || chrome_title_junk?
        else
          raise ArgumentError, "unknown hard_junk mode: #{mode.inspect}"
        end
      end

      private

      def chrome_title_junk? # rubocop:disable Metrics/CyclomaticComplexity
        (selected_anchor_present && recommended_title && shallow && weak_signals?) ||
          (selected_anchor_present && utility_prefix_title && high_confidence_utility_destination && weak_signals?)
      end
    end
  end
end
