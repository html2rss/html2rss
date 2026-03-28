# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class SemanticHtml
        ##
        # Selects the best content-like anchor from a semantic container.
        #
        # The selector turns raw DOM anchors into ranked facts so semantic
        # scraping can reason about link intent instead of DOM order. It favors
        # heading-aligned article links and suppresses utility links, duplicate
        # destinations, and weak textless affordances.
        class AnchorSelector # rubocop:disable Metrics/ClassLength
          AnchorFacts = Data.define(
            :anchor,
            :text,
            :url,
            :destination,
            :segments,
            :meaningful_text,
            :content_like_destination,
            :heading_anchor,
            :heading_text_match,
            :score
          )

          HEADING_SELECTOR = HtmlExtractor::HEADING_TAGS.join(',').freeze
          UTILITY_LANDMARK_TAGS = %w[nav aside footer menu].freeze

          def initialize(base_url)
            @base_url = base_url
            @link_heuristics = LinkHeuristics.new(base_url)
          end

          ##
          # Chooses the single anchor that best represents the story contained
          # in a semantic block.
          #
          # Ranking is scoped to one container at a time. That keeps the logic
          # local, makes duplicate links to the same destination collapse into
          # one candidate, and avoids page-wide heuristics leaking across cards.
          #
          # @param container [Nokogiri::XML::Element] semantic container being evaluated
          # @return [Nokogiri::XML::Element, nil] selected primary anchor or nil when none qualify
          def primary_anchor_for(container)
            facts_for(container).max_by(&:score)&.anchor
          end

          private

          attr_reader :base_url

          def facts_for(container)
            heading = heading_for(container)
            heading_text = visible_text(heading)

            container.css(HtmlExtractor::MAIN_ANCHOR_SELECTOR).each_with_object({}) do |anchor, best_by_destination|
              next if anchor.path.match?(Html::TAGS_TO_IGNORE)

              facts = build_facts(anchor, heading, heading_text)
              next unless facts

              keep_stronger_fact(best_by_destination, facts)
            end.values
          end

          def build_facts(anchor, heading, heading_text) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            text = visible_text(anchor)
            meaningful_text = meaningful_text?(text)
            ancestors = anchor.ancestors.to_a
            destination_facts = normalized_destination(anchor)
            return unless destination_facts

            content_like_destination = destination_facts.content_path
            heading_anchor = heading_anchor?(ancestors, heading)
            return if suppress_utility_text?(text, destination_facts, heading_anchor:)
            return if ineligible_anchor?(anchor, ancestors, meaningful_text, destination_facts)

            heading_text_match = heading_text_match?(heading_text, text, meaningful_text)
            return unless heading_anchor || content_like_anchor?(meaningful_text, content_like_destination)

            AnchorFacts.new(
              anchor:,
              text:,
              url: destination_facts.url,
              destination: destination_facts.destination,
              segments: destination_facts.segments,
              meaningful_text:,
              content_like_destination:,
              heading_anchor:,
              heading_text_match:,
              score: score_anchor(meaningful_text, content_like_destination, heading_anchor, heading_text_match)
            )
          end

          def ineligible_anchor?(anchor, ancestors, meaningful_text, destination_facts)
            destination_facts.high_confidence_utility_destination ||
              icon_only_anchor?(anchor, meaningful_text) ||
              utility_landmark_anchor?(ancestors)
          end

          def keep_stronger_fact(best_by_destination, facts)
            current = best_by_destination[facts.destination]
            return best_by_destination[facts.destination] = facts unless current
            return if current.score >= facts.score

            best_by_destination[facts.destination] = facts
          end

          def content_like_anchor?(meaningful_text, content_like_destination)
            meaningful_text || content_like_destination
          end

          def score_anchor(meaningful_text, content_like_destination, heading_anchor, heading_text_match)
            score = 0
            score += 100 if heading_anchor
            score += 20 if heading_text_match
            score += 10 if meaningful_text
            score += 10 if content_like_destination
            score
          end

          def heading_anchor?(ancestors, heading)
            heading && ancestors.include?(heading)
          end

          def heading_text_match?(heading_text, text, meaningful_text)
            meaningful_text && meaningful_text?(heading_text) && heading_text == text
          end

          def heading_for(container)
            container.at_css(HEADING_SELECTOR)
          end

          def icon_only_anchor?(anchor, meaningful_text)
            !meaningful_text && anchor.at_css('img, svg')
          end

          def normalized_destination(anchor)
            @link_heuristics.destination_facts(anchor)
          end

          def meaningful_text?(text)
            text.scan(/\p{Alnum}+/).any?
          end

          def utility_text?(text)
            @link_heuristics.utility_text?(text)
          end

          def suppress_utility_text?(text, destination_facts, heading_anchor:)
            return false if destination_facts.content_path

            utility_text?(text) &&
              (
                destination_facts.high_confidence_utility_destination ||
                (!heading_anchor && !destination_facts.strong_post_suffix)
              )
          end

          def utility_landmark_anchor?(ancestors)
            ancestors.any? { |node| UTILITY_LANDMARK_TAGS.include?(node.name) }
          end

          def visible_text(node)
            return '' unless node

            HtmlExtractor.extract_visible_text(node).to_s.strip
          end
        end
      end
    end
  end
end
