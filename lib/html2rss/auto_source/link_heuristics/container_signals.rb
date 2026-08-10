# frozen_string_literal: true

module Html2rss
  class AutoSource
    class LinkHeuristics
      # Container observations used to compute quality/junk scores.
      ContainerSignals = Data.define(
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
        # @return [Integer] positive quality contribution for ranking
        def quality_score # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          score = 0
          score += 40 if title_word_count >= 3
          score += 15 if title_word_count >= 7
          score += 20 if path_length > 6
          score += 15 if content_path
          score += 15 if publish_marker
          score += 10 if descriptive_context
          score += 10 if article_container
          score += 10 if content_tokens
          score
        end

        # @return [Integer] junk penalty subtracted from quality
        def junk_score # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          score = 0
          score += 25 if non_content_utility_path?
          score += 15 if utility_prefix_title && title_word_count <= 6
          score += 10 if shallow
          score += 10 if weak_container?
          score += 10 if recommended_title && !content_path
          score += 5 if high_confidence_junk_path
          score += 15 if junk_tokens
          score
        end

        # @return [Integer] quality minus junk for stable ranking
        def final_score = quality_score - junk_score

        # @return [Boolean] true when the entry should be dropped before ranking
        def hard_junk? # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          weak = weak_article_candidate?

          high_confidence_junk_path ||
            (selected_anchor_present && recommended_title && shallow && weak) ||
            (selected_anchor_present && utility_prefix_title &&
              high_confidence_utility_destination && weak)
        end

        private

        # @return [Boolean] true when article evidence is too weak to keep
        def weak_article_candidate?
          [article_container, publish_marker, descriptive_context, content_path].count(&:itself) < 2
        end

        def non_content_utility_path?
          utility_path && !content_path && !strong_post_suffix
        end

        def weak_container? = !publish_marker && !descriptive_context
      end
    end
  end
end
