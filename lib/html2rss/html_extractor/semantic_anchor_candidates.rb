# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    ##
    # Builds ranked anchor facts for one semantic content container.
    class SemanticAnchorCandidates
      # Anchor candidate plus scoring signals used by semantic anchor ranking.
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
      ) do
        # @param candidate [Candidate] eligible semantic anchor candidate
        # @return [AnchorFacts] serializable facts used for ranking and dedupe
        def self.from_candidate(candidate)
          new(
            **candidate.anchor_identity_attributes,
            **candidate.anchor_signal_attributes,
            score: Score.new(candidate).value
          )
        end
      end

      # Shared context for all anchors in one semantic container.
      class Context
        attr_reader :container

        # Ancestor tags that usually indicate navigation/utility regions.
        UTILITY_LANDMARK_TAGS = %w[nav aside footer menu].freeze

        # @param container [Nokogiri::XML::Node] semantic container
        # @param link_heuristics [Html2rss::AutoSource::Scraper::LinkHeuristics] destination/text heuristics
        def initialize(container, link_heuristics:)
          @container = container
          @link_heuristics = link_heuristics
        end

        # @return [Nokogiri::XML::Node, nil] heading used to identify title anchors
        def heading
          @heading ||= @container.at_css(HtmlExtractor::HEADING_TAGS.join(','))
        end

        # @return [String] visible heading text
        def heading_text
          @heading_text ||= visible_text(heading)
        end

        # @param node [Nokogiri::XML::Node, nil] node to extract text from
        # @return [String] visible text for the node
        def visible_text(node)
          return '' unless node

          (@visible_texts ||= {}.compare_by_identity)[node] ||= HtmlExtractor.extract_visible_text(node).to_s.strip
        end

        # @param anchor [Nokogiri::XML::Node] anchor candidate
        # @return [Html2rss::AutoSource::Scraper::LinkHeuristics::DestinationFacts, nil] destination facts
        def destination_facts(anchor)
          @link_heuristics.destination_facts(anchor)
        end

        # @param text [String] visible anchor text
        # @return [Boolean] true when text is utility chrome
        def utility_text?(text)
          @link_heuristics.utility_text?(text)
        end
      end

      # One anchor plus the facts needed to decide whether it represents content.
      class Candidate
        attr_reader :anchor

        # @param anchor [Nokogiri::XML::Node] anchor candidate
        # @param context [Context] semantic container context
        def initialize(anchor, context)
          @anchor = anchor
          @context = context
        end

        # @return [AnchorFacts, nil] ranked anchor facts when the anchor is eligible
        def facts
          return unless destination_facts
          return if utility_text_suppressed? || ineligible_anchor?
          return unless representative_content_anchor?

          AnchorFacts.from_candidate(self)
        end

        # @return [Html2rss::AutoSource::Scraper::LinkHeuristics::DestinationFacts, nil] destination facts
        def destination_facts
          @destination_facts ||= @context.destination_facts(@anchor)
        end

        # @return [String] visible anchor text
        def text
          @text ||= @context.visible_text(@anchor)
        end

        # @return [Hash] anchor identity attributes used to build AnchorFacts
        def anchor_identity_attributes
          {
            anchor:,
            text:,
            url: destination_facts.url,
            destination: destination_facts.destination,
            segments: destination_facts.segments
          }
        end

        # @return [Hash] anchor signal attributes used to build AnchorFacts
        def anchor_signal_attributes
          {
            meaningful_text: meaningful_text?,
            content_like_destination: content_like_destination?,
            heading_anchor: heading_anchor?,
            heading_text_match: heading_text_match?
          }
        end

        # @return [Boolean] true when visible anchor text has words
        def meaningful_text?
          @meaningful_text ||= text.match?(/\p{Alnum}/)
        end

        # @return [Boolean] true when the destination route has content signals
        def content_like_destination?
          destination_facts.content_path
        end

        # @return [Boolean] true when the anchor is inside the selected heading
        def heading_anchor?
          heading = @context.heading
          return false unless heading

          curr = @anchor
          container = @context.container
          while curr.respond_to?(:parent)
            return true if curr == heading
            break if curr == container

            curr = curr.parent
          end
          false
        end

        # @return [Boolean] true when anchor text exactly matches heading text
        def heading_text_match?
          heading_text = @context.heading_text

          meaningful_text? &&
            heading_text.match?(/\p{Alnum}/) &&
            heading_text == text
        end

        private

        def representative_content_anchor?
          meaningful_text? || content_like_destination? || heading_anchor?
        end

        def utility_text_suppressed?
          !content_like_destination? &&
            @context.utility_text?(text) &&
            (destination_facts.high_confidence_utility_destination || non_heading_weak_post?)
        end

        def non_heading_weak_post?
          !heading_anchor? && !destination_facts.strong_post_suffix
        end

        def ineligible_anchor?
          destination_facts.high_confidence_utility_destination ||
            icon_only_anchor? ||
            utility_landmark_ancestor?
        end

        def utility_landmark_ancestor?
          curr = @anchor.parent
          container = @context.container
          while curr.respond_to?(:parent)
            return true if Context::UTILITY_LANDMARK_TAGS.include?(curr.name)
            break if curr == container

            curr = curr.parent
          end
          false
        end

        def icon_only_anchor?
          !meaningful_text? && @anchor.at_css('img, svg')
        end
      end

      # Scores an eligible semantic anchor candidate.
      class Score
        # Score weights keyed by candidate signal predicate.
        RULES = {
          heading_anchor?: 100,
          heading_text_match?: 20,
          meaningful_text?: 10,
          content_like_destination?: 10
        }.freeze

        # @param candidate [Candidate] eligible semantic anchor candidate
        def initialize(candidate)
          @candidate = candidate
        end

        # @return [Integer] ranking score
        def value
          RULES.sum { |predicate, weight| @candidate.public_send(predicate) ? weight : 0 }
        end
      end

      # Keeps the strongest semantic anchor fact for each destination.
      class DestinationWinners
        def initialize
          @winners = {}
        end

        # @return [Array<AnchorFacts>] strongest candidate per destination
        def to_a
          @winners.values
        end

        # @param facts [AnchorFacts] candidate anchor facts
        # @return [void]
        def add(facts)
          destination = facts.destination
          @winners[destination] = stronger_fact(@winners[destination], facts)
        end

        private

        def stronger_fact(current, candidate)
          return candidate unless current

          current.score >= candidate.score ? current : candidate
        end
      end

      # @param container [Nokogiri::XML::Node] semantic container
      # @param link_heuristics [Html2rss::AutoSource::Scraper::LinkHeuristics] destination/text heuristics
      def initialize(container, link_heuristics:)
        @container = container
        @context = Context.new(container, link_heuristics:)
      end

      # @return [Array<AnchorFacts>] strongest candidate per destination
      def to_a
        @container.css(HtmlExtractor::MAIN_ANCHOR_SELECTOR)
                  .each_with_object(DestinationWinners.new) { |anchor, winners| add_anchor(anchor, winners) }
                  .to_a
      end

      private

      def add_anchor(anchor, winners)
        return if HtmlExtractor.ignored_container_path?(anchor)

        facts = Candidate.new(anchor, @context).facts
        winners.add(facts) if facts
      end
    end
  end
end
