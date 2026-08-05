# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class LinkHeuristics
        ##
        # Turns container DOM observations into ContainerSignals inputs.
        #
        # Owns publish markers, headings, visible text, and class/id tokens so
        # LinkHeuristics can keep eligibility policy and ContainerSignals can
        # keep scoring without re-reading the DOM.
        class ContainerAssessor
          # Token pattern for content-like class/id markers on containers.
          CONTENT_TOKEN_REGEXP = begin
            words = PathClassifier::SEGMENT_SETS.fetch(:content)
            /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
          end.freeze

          # Token pattern for junk/utility class/id markers on containers.
          JUNK_TOKEN_REGEXP = begin
            words = PathClassifier::SEGMENT_SETS.fetch(:utility)
            /(?:^|\s|[-_])(#{Regexp.union(words.to_a).source})(?:\s|[-_]|$)/i
          end.freeze

          # @param text_classifier [TextClassifier] shared utility/recommended text policy
          def initialize(text_classifier:)
            @text_classifier = text_classifier
          end

          ##
          # Observes a container and builds ranking signals, including hard-junk.
          #
          # @param container [Nokogiri::XML::Node] semantic container node
          # @param selected_anchor [Nokogiri::XML::Node, nil] primary anchor for the container
          # @param destination_facts [DestinationFacts, nil] route facts for the selected anchor
          # @return [ContainerSignals] observation + scoring signals for the container
          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def call(container, selected_anchor, destination_facts:)
            title = entry_title(container, selected_anchor)
            tokens = container_tokens(container)

            ContainerSignals.new(
              title_word_count: word_count(title),
              path_length: destination_facts&.url&.path.to_s.length,
              content_path: destination_facts&.content_path,
              publish_marker: publish_marker?(container),
              descriptive_context: descriptive_context?(visible_text(container), title),
              article_container: container.name == 'article',
              content_tokens: content_tokens?(tokens),
              junk_tokens: junk_tokens?(tokens),
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
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          private

          def publish_marker?(container)
            (@publish_markers ||= {}.compare_by_identity)[container] ||=
              !!container.at_css('time, [datetime], [itemprop="datePublished"], [itemprop="dateModified"]')
          end

          def descriptive_context?(container_text, title)
            snippet = container_text.to_s.sub(/\A#{Regexp.escape(title.to_s)}/i, '')
            snippet.length > 30 && word_count(snippet) >= 8
          end

          def heading_for(container)
            (@headings ||= {}.compare_by_identity)[container] ||=
              container.at_css(HtmlNavigator::HEADING_TAGS.join(','))
          end

          def visible_text(node)
            return '' unless node

            (@visible_texts ||= {}.compare_by_identity)[node] ||= HtmlNavigator.extract_visible_text(node).to_s.strip
          end

          def entry_title(container, selected_anchor) = visible_text(heading_for(container) || selected_anchor)

          def word_count(text)
            (@word_counts ||= {})[text] ||= begin
              count = 0
              text.to_s.scan(/\p{Alnum}+/) { count += 1 }
              count
            end
          end

          def container_tokens(container)
            (@container_tokens ||= {}.compare_by_identity)[container] ||= "#{container['class']} #{container['id']}"
          end

          def content_tokens?(tokens) = tokens.to_s.match?(CONTENT_TOKEN_REGEXP)

          def junk_tokens?(tokens) = tokens.to_s.match?(JUNK_TOKEN_REGEXP)
        end
      end
    end
  end
end
