# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Observes an SST container and builds typed {Observation} score inputs.
    class ContainerAssessor
      # Microdata itemprop values treated as publish/update markers.
      PUBLISH_ITEMPROPS = %w[datePublished dateModified].freeze

      # Matches content-like tokens in class/id strings.
      CONTENT_TOKEN_REGEXP = begin
        words = LinkDestination::PathClassifier::SEGMENT_SETS.fetch(:content)
        /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
      end.freeze

      # Matches utility/junk tokens in class/id strings.
      JUNK_TOKEN_REGEXP = begin
        words = LinkDestination::PathClassifier::SEGMENT_SETS.fetch(:utility)
        /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
      end.freeze

      # @param text_classifier [LinkDestination::TextClassifier]
      def initialize(text_classifier: LinkDestination::TextClassifier.new)
        @text_classifier = text_classifier
      end

      ##
      # @param container [SST::Node]
      # @param selected_anchor [SST::Node, nil]
      # @param destination_facts [LinkDestination::DestinationFacts, nil]
      # @return [Observation]
      def call(container, selected_anchor, destination_facts:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        title = entry_title(container, selected_anchor)
        tokens = "#{container.attrs.class_attr} #{container.attrs.id}"

        Observation.new(
          title_word_count: word_count(title),
          path_length: destination_facts&.url&.path.to_s.length,
          content_path: destination_facts&.content_path,
          publish_marker: publish_marker?(container),
          descriptive_context: descriptive_context?(container.visible_text, title),
          article_container: container.name == :article,
          content_tokens: tokens.match?(CONTENT_TOKEN_REGEXP),
          junk_tokens: tokens.match?(JUNK_TOKEN_REGEXP),
          utility_prefix_title: @text_classifier.utility_prefix?(title),
          recommended_title: @text_classifier.recommended?(title),
          utility_path: destination_facts&.utility_path,
          strong_post_suffix: destination_facts&.strong_post_suffix,
          shallow: destination_facts&.shallow,
          high_confidence_junk_path: destination_facts&.high_confidence_junk_path,
          high_confidence_utility_destination: destination_facts&.high_confidence_utility_destination,
          selected_anchor_present: !selected_anchor.nil?
        )
      end

      private

      def publish_marker?(container)
        !!container.find do |n|
          n.name == :time ||
            n.attrs.datetime ||
            PUBLISH_ITEMPROPS.include?(n.attrs.itemprop.to_s)
        end
      end

      def descriptive_context?(container_text, title)
        snippet = container_text.to_s.sub(/\A#{Regexp.escape(title.to_s)}/i, '')
        snippet.length > 30 && word_count(snippet) >= 8
      end

      def entry_title(container, selected_anchor)
        heading = container.find(&:heading?)
        source = heading || selected_anchor
        source ? source.visible_text.to_s.strip : ''
      end

      def word_count(text)
        text.to_s.scan(/\p{Alnum}+/).size
      end
    end
  end
end
