# frozen_string_literal: true

module Html2rss
  module LinkDestination
    ##
    # Noise / junk chrome eligibility for SST anchors (port of LinkHeuristics#noise_anchor?).
    class NoisePolicy
      # Child tag names that mark icon-only anchors as noise.
      ICON_NAMES = %i[img svg].freeze

      # Query parameters that name a page, so a link carrying one is no section hub (+/read?id=123+).
      IDENTITY_PARAMS = %w[id aid p].freeze

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
      # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
      def noise_anchor?(text:, destination_facts:, anchor: nil, container: nil,
                        heading_anchor: false, utility_landmark_ancestor: false)
        return true unless destination_facts

        destination_facts.taxonomy_path ||
          short_utility_label?(text, destination_facts) || list_hub_label?(text, destination_facts, heading_anchor:) ||
          recommended_chrome?(text, destination_facts, heading_anchor:) ||
          (@link_resolver.utility_prefix_text?(text) && destination_facts.high_confidence_utility_destination) ||
          (@link_resolver.utility_text?(text) && destination_facts.vanity_path) ||
          utility_text_chrome?(text, destination_facts, heading_anchor:, anchor:, container:) ||
          icon_only_anchor?(anchor, text) ||
          concealed_anchor?(anchor) ||
          utility_landmark_ancestor
      end

      private

      def short_utility_label?(text, destination_facts)
        destination_facts.utility_path &&
          !destination_facts.content_path &&
          !destination_facts.strong_post_suffix &&
          !WordCount.at_least?(text, 4)
      end

      # A section link labelled with a list-level term of a page-only language ("see all"): a path of one or two
      # segments, none a content word, ending in a plain word (no hyphen, digit, underscore or dot, so never a post
      # suffix), and no identity query parameter (+/read?id=123+ names a page, not a hub).
      # A card whose only link is such a label is lost; a hyphenated hub still passes.
      def list_hub_label?(text, destination_facts, heading_anchor:)
        segments = destination_facts.segments
        return false if heading_anchor || destination_facts.content_path
        return false unless segments.size.between?(1, 2) && !segments.last.match?(/[-\d_.]/)

        @link_resolver.list_more_text?(text) && !destination_facts.url.query_values.keys.intersect?(IDENTITY_PARAMS)
      end

      def recommended_chrome?(text, destination_facts, heading_anchor:)
        !heading_anchor && @link_resolver.recommended_text?(text) && destination_facts.shallow
      end

      def utility_text_chrome?(text, destination_facts, heading_anchor:, anchor:, container:)
        return false if destination_facts.content_path
        return false unless @link_resolver.utility_chrome_text?(text)
        return false if heading_anchor || destination_facts.strong_post_suffix

        !(@link_resolver.page_only_chrome_text?(text) && sole_link_of_headed_card?(anchor, container))
      end

      # A card with a real, unlinked heading whose only link is this anchor: its label is the card's link, not
      # chrome beside it (a page-only noun such as +评论+ labels the story link).
      def sole_link_of_headed_card?(anchor, container)
        return false unless container

        heading = container.find(&:heading?)
        heading&.visible_text.to_s.match?(/\p{Alnum}/) &&
          container.find { |node| node.link? && !node.equal?(anchor) }.nil?
      end

      # An anchor a sighted reader does not see, such as the off-screen accessibility twin of a teaser
      # link ({Html::Visibility.concealed?}), is never the item.
      def concealed_anchor?(anchor)
        return false unless anchor

        attrs = anchor.attrs
        Html::Visibility.concealed?(attrs.class_names, style: attrs.style, hidden: attrs.raw.key?('hidden'))
      end

      def icon_only_anchor?(anchor, text)
        return false unless anchor
        return false if text.to_s.match?(/\p{Alnum}/)

        !!anchor.find { |n| ICON_NAMES.include?(n.name) }
      end
    end
  end
end
