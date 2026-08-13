# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Closed set of feature identifiers used by the scoring registry.
    module FeatureId
      # Closed set of allowed feature identifier symbols.
      IDS = %i[
        title_word_count_ge3
        title_word_count_ge7
        path_length_gt6
        content_path
        publish_marker
        descriptive_context
        article_container
        content_tokens
        non_content_utility_path
        utility_prefix_title_short
        shallow
        weak_container
        recommended_title_non_content
        high_confidence_junk_path
        junk_tokens
        heading_anchor
        heading_text_match
        meaningful_text
        content_like_destination
        cluster_size
        cluster_avg_words
        cluster_heading
        cluster_time
        cluster_date
      ].to_set.freeze

      module_function

      ##
      # @param id [Symbol]
      # @return [Symbol]
      # @raise [ArgumentError] when id is not in the closed set
      def assert!(id)
        raise ArgumentError, "unknown FeatureId: #{id.inspect}" unless IDS.include?(id)

        id
      end
    end
  end
end
