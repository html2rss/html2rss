# frozen_string_literal: true

module Html2rss
  module LinkDestination
    ##
    # Noise / junk chrome eligibility for SST anchors (port of LinkHeuristics#noise_anchor?).
    class NoisePolicy
      # Child tag names that mark icon-only anchors as noise.
      ICON_NAMES = %i[img svg].freeze

      # @param link_resolver [LinkResolver]
      def initialize(link_resolver:)
        @link_resolver = link_resolver
      end

      ##
      # @param text [String]
      # @param destination_facts [LinkDestination::DestinationFacts, nil]
      # @param anchor [SST::Node, nil]
      # @param container [SST::Node, nil]
      # @param heading_anchor [Boolean]
      # @param utility_landmark_ancestor [Boolean] pre-computed by Segmenter tree walk
      # @return [Boolean]
      # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity, Lint/UnusedMethodArgument
      def noise_anchor?(text:, destination_facts:, anchor: nil, container: nil,
                        heading_anchor: false, utility_landmark_ancestor: false)
        return true unless destination_facts

        destination_facts.taxonomy_path ||
          short_utility_label?(text, destination_facts) ||
          recommended_chrome?(text, destination_facts, heading_anchor:) ||
          (@link_resolver.utility_prefix_text?(text) && destination_facts.high_confidence_utility_destination) ||
          (@link_resolver.utility_text?(text) && destination_facts.vanity_path) ||
          utility_text_chrome?(text, destination_facts, heading_anchor:) ||
          icon_only_anchor?(anchor, text) ||
          utility_landmark_ancestor
      end

      private

      def short_utility_label?(text, destination_facts)
        destination_facts.utility_path &&
          !destination_facts.content_path &&
          !destination_facts.strong_post_suffix &&
          text.to_s.scan(/\p{Alnum}+/).size <= 3
      end

      def recommended_chrome?(text, destination_facts, heading_anchor:)
        !heading_anchor && @link_resolver.recommended_text?(text) && destination_facts.shallow
      end

      def utility_text_chrome?(text, destination_facts, heading_anchor:)
        return false if destination_facts.content_path
        return false unless @link_resolver.utility_text?(text)

        !heading_anchor && !destination_facts.strong_post_suffix
      end

      def icon_only_anchor?(anchor, text)
        return false unless anchor
        return false if text.to_s.match?(/\p{Alnum}/)

        !!anchor.find { |n| ICON_NAMES.include?(n.name) }
      end
    end
  end
end
