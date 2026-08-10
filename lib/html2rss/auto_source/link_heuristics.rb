# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Shared link eligibility and scoring policy for AutoSource scrapers.
    #
    # Scrapers collect DOM observations; this module owns junk/noise rules and
    # numeric weights so eligibility policy stays in one place.
    class LinkHeuristics
      # @param base_url [String, Html2rss::Url] page URL used to resolve relative hrefs
      def initialize(base_url)
        @base_url = base_url
        @text_classifier = TextClassifier.new
        @container_assessor = ContainerAssessor.new(text_classifier: @text_classifier)
      end

      # Builds normalized destination facts for an anchor element or href string.
      #
      # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
      # @return [DestinationFacts, nil] normalized destination facts, or nil for blank/invalid URLs
      def destination_facts(anchor_or_href)
        return node_facts[anchor_or_href] if node_facts.key?(anchor_or_href)

        href = HrefExtractor.call(anchor_or_href)
        return unless href

        res = memoized_destination_facts(href)

        node_facts[anchor_or_href] = res if anchor_or_href.is_a?(Nokogiri::XML::Node)
        res
      rescue ArgumentError
        nil
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text matches a utility label
      def utility_text?(text) = @text_classifier.utility?(text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text begins with a utility label
      def utility_prefix_text?(text) = @text_classifier.utility_prefix?(text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text identifies recommendation chrome
      def recommended_text?(text) = @text_classifier.recommended?(text)

      ##
      # Whether an anchor is junk chrome rather than a content permalink.
      #
      # One eligibility home for Html and SemanticHtml: taxonomy/utility text
      # rules plus optional DOM checks (icon-only, utility landmarks).
      #
      # @param text [String, #to_s] visible anchor text
      # @param destination_facts [DestinationFacts, nil] route facts for the href
      # @param anchor [Nokogiri::XML::Node, nil] anchor node for icon/landmark checks
      # @param container [Nokogiri::XML::Node, nil] content container bounding landmark walks
      # @param heading_anchor [Boolean] whether the anchor is the container heading link
      # @return [Boolean] true when the anchor should be ignored
      def noise_anchor?(text:, destination_facts:, anchor: nil, container: nil, heading_anchor: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        return true unless destination_facts

        destination_facts.taxonomy_path ||
          short_utility_label?(text, destination_facts) ||
          recommended_chrome?(text, destination_facts, heading_anchor:) ||
          (utility_prefix_text?(text) && destination_facts.high_confidence_utility_destination) ||
          (utility_text?(text) && destination_facts.vanity_path) ||
          utility_text_chrome?(text, destination_facts, heading_anchor:) ||
          icon_only_anchor?(anchor, text) ||
          utility_landmark_ancestor?(anchor, container)
      end

      ##
      # Observes a container and builds ranking signals, including hard-junk.
      #
      # Delegates DOM observation to ContainerAssessor so SemanticHtml only
      # orchestrates candidates and extraction, while ContainerSignals keeps
      # scoring policy.
      #
      # @param container [Nokogiri::XML::Node] semantic container node
      # @param selected_anchor [Nokogiri::XML::Node, nil] primary anchor for the container
      # @param destination_facts [DestinationFacts, nil] route facts for the selected anchor
      # @return [ContainerSignals] observation + scoring signals for the container
      def assess_container(container, selected_anchor, destination_facts:)
        @container_assessor.call(container, selected_anchor, destination_facts:)
      end

      private

      def short_utility_label?(text, destination_facts)
        destination_facts.utility_path &&
          !destination_facts.content_path &&
          !destination_facts.strong_post_suffix &&
          text.to_s.scan(/\p{Alnum}+/).size <= 3
      end

      def recommended_chrome?(text, destination_facts, heading_anchor:)
        # Heading-linked titles may start with "Recommended …" while still being
        # real posts; container hard_junk? owns that call with publish markers.
        !heading_anchor && recommended_text?(text) && destination_facts.shallow
      end

      def utility_text_chrome?(text, destination_facts, heading_anchor:)
        return false if destination_facts.content_path
        return false unless utility_text?(text)

        !heading_anchor && !destination_facts.strong_post_suffix
      end

      def icon_only_anchor?(anchor, text)
        return false unless anchor

        !text.to_s.match?(/\p{Alnum}/) && !anchor.at_css('img, svg').nil?
      end

      def utility_landmark_ancestor?(anchor, container)
        return false unless anchor && container

        condition = lambda { |node|
          node == container || Html2rss::Html::Navigator::UTILITY_LANDMARK_TAGS.include?(node.name)
        }
        landmark = Html2rss::Html::Navigator.parent_until_condition(anchor.parent, condition)

        !landmark.nil? && landmark != container
      end

      def node_facts
        @node_facts ||= {}.compare_by_identity
      end

      def memoized_destination_facts(href)
        (@destination_facts ||= {})[href] ||= begin
          url = Html2rss::Url.from_relative(href, @base_url)
          DestinationFacts.build(url)
        end
      end
    end
  end
end
