# frozen_string_literal: true

module Html2rss
  class AutoSource
    class LinkHeuristics
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
      ) do
        # @param url [Html2rss::Url] normalized destination URL
        # @return [DestinationFacts] route facts for downstream link scoring
        def self.build(url) # rubocop:disable Metrics/MethodLength
          classifier = PathClassifier.new(url.path_segments)

          new(
            url:,
            destination: url.to_s,
            segments: classifier.segments,
            strong_post_suffix: classifier.strong_post_suffix?,
            content_path: classifier.content_path?,
            utility_path: classifier.utility_path?,
            taxonomy_path: classifier.taxonomy_path?,
            vanity_path: classifier.vanity_path?,
            shallow: classifier.shallow?,
            high_confidence_junk_path: classifier.junk_path?,
            high_confidence_utility_destination: classifier.utility_destination?
          )
        end
      end
    end
  end
end
