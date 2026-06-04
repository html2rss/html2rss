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
        class AnchorSelector
          # Comma-separated heading selector used for heading/anchor matching.
          HEADING_SELECTOR = HtmlExtractor::HEADING_TAGS.join(',').freeze

          # @param base_url [String, Html2rss::Url] page URL used to normalize href destinations
          def initialize(base_url)
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

          def facts_for(container)
            HtmlExtractor::SemanticAnchorCandidates.new(
              container,
              link_heuristics: @link_heuristics
            ).to_a
          end
        end
      end
    end
  end
end
