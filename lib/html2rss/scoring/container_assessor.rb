# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Observes an SST container and builds typed {Observation} score inputs.
    class ContainerAssessor
      # Microdata itemprop values treated as publish/update markers.
      PUBLISH_ITEMPROPS = %w[datePublished dateModified].freeze
      # Letter/digit runs ({WordCount.runs}) beyond the title that make a container descriptive.
      DESCRIPTIVE_RUNS = 8

      # @param text_classifier [LinkDestination::TextClassifier]
      # @param content_token_regexp [Regexp]
      # @param junk_token_regexp [Regexp]
      def initialize(text_classifier: LinkDestination::TextClassifier.new,
                     content_token_regexp: LinkResolver::CONTENT_TOKEN_REGEXP,
                     junk_token_regexp: LinkResolver::JUNK_TOKEN_REGEXP)
        @text_classifier = text_classifier
        @content_token_regexp = content_token_regexp
        @junk_token_regexp = junk_token_regexp
      end

      ##
      # @param container [SST::Node]
      # @param selected_anchor [SST::Node, nil]
      # @param destination_facts [LinkDestination::DestinationFacts, nil]
      # @return [Observation]
      def call(container, selected_anchor, destination_facts:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        source = container.find(&:heading?) || selected_anchor
        title = source ? source.visible_text.to_s.strip : ''
        tokens = "#{container.attrs.class_attr} #{container.attrs.id}"

        Observation.new(
          title_runs: source ? source.run_count : 0,
          path_length: destination_facts&.url&.path.to_s.length,
          content_path: destination_facts&.content_path,
          publish_marker: publish_marker?(container),
          descriptive_context: descriptive_context?(container.visible_text, title),
          article_container: container.name == :article,
          content_tokens: tokens.match?(@content_token_regexp),
          junk_tokens: tokens.match?(@junk_token_regexp),
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
        snippet = without_title_prefix(container_text.to_s, title)
        snippet.length > 30 && WordCount.runs(snippet, ceiling: DESCRIPTIVE_RUNS) == DESCRIPTIVE_RUNS
      end

      # Case-insensitive prefix strip compared by character count, so multi-character
      # case folds (e.g. "ß" vs "ss") do not match; the title is then left in the snippet.
      def without_title_prefix(text, title)
        return text unless text[0, title.length].casecmp?(title)

        text[title.length..]
      end
    end
  end
end
