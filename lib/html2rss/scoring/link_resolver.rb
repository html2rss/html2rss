# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Resolves href strings into memoized LinkDestination::DestinationFacts for one page base URL.
    class LinkResolver
      # Captures the href portion before a fragment for memoization keys.
      HREF_BASE_PATTERN = /\A([^#]*)/

      # Matches content-like tokens in class/id strings (from PathClassifier vocabulary).
      CONTENT_TOKEN_REGEXP = begin
        words = LinkDestination::PathClassifier::SEGMENT_SETS.fetch(:content)
        /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
      end.freeze

      # Matches utility/junk tokens in class/id strings (from PathClassifier vocabulary).
      JUNK_TOKEN_REGEXP = begin
        words = LinkDestination::PathClassifier::SEGMENT_SETS.fetch(:utility)
        /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
      end.freeze

      # @param base_url [String, Html2rss::Url]
      def initialize(base_url)
        @base_url = base_url
        @by_href = {}
        @by_node = {}.compare_by_identity
        @text_classifier = LinkDestination::TextClassifier.new
      end

      # @return [LinkDestination::TextClassifier]
      attr_reader :text_classifier

      ##
      # @param node_or_href [SST::Node, String, #to_s]
      # @return [LinkDestination::DestinationFacts, nil]
      def destination_facts(node_or_href)
        return @by_node[node_or_href] if node_or_href.is_a?(SST::Node) && @by_node.key?(node_or_href)

        href = extract_href(node_or_href)
        return unless href

        facts = (@by_href[href] ||= build_facts(href))
        @by_node[node_or_href] = facts if node_or_href.is_a?(SST::Node)
        facts
      rescue ArgumentError
        nil
      end

      ##
      # @param text [String, #to_s]
      # @return [Boolean]
      def utility_text?(text) = @text_classifier.utility?(text)

      ##
      # @param text [String, #to_s]
      # @return [Boolean]
      def utility_prefix_text?(text) = @text_classifier.utility_prefix?(text)

      ##
      # @param text [String, #to_s]
      # @return [Boolean]
      def recommended_text?(text) = @text_classifier.recommended?(text)

      private

      def extract_href(node_or_href)
        raw = case node_or_href
              when SST::Node then node_or_href.attrs.href
              else node_or_href
              end
        return unless raw

        base = raw.to_s[HREF_BASE_PATTERN, 1].to_s.strip
        base unless base.empty?
      end

      def build_facts(href)
        url = Html2rss::Url.from_relative(href, @base_url)
        LinkDestination::DestinationFacts.build(url)
      end
    end
  end
end
