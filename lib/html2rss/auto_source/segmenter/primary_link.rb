# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Selects the strongest content-like primary link of a container
      # (port of Discovery::SemanticAnchorCandidates). A card without a qualifying link of its own
      # falls back to the anchor that wraps the whole card.
      class PrimaryLink
        # @param segmenter [Segmenter]
        def initialize(segmenter)
          @segmenter = segmenter
          @index = segmenter.index
          @link_resolver = segmenter.link_resolver
          @noise_policy = segmenter.noise_policy
        end

        ##
        # @param container [SST::Node]
        # @return [SST::Node, nil]
        def select(container) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          winners = {}

          container.find_all(&:link?).each do |anchor|
            next if @index.ignored_chrome?(anchor)

            facts = candidate_facts(anchor, container)
            next unless facts

            dest = facts[:destination]
            current = winners[dest]
            winners[dest] = facts if current.nil? || facts[:score] > current[:score]
          end

          winners.values.max_by { |f| f[:score] }&.fetch(:anchor) || wrapping_link(container)
        end

        private

        # The nearest ancestor link when it wraps a whole card.
        def wrapping_link(container)
          link = @index.parent_until(@index.parent_of(container), :link?.to_proc)
          return unless link && !@index.ignored_chrome?(link) && card_link?(link)

          link if candidate_facts(link, container)
        end

        # A card link holds the card's heading and no other link. A link holding other links is a
        # parser-recovered unclosed anchor spanning a region; one without a heading wraps a fragment
        # of a story (such as one live-blog entry), not a card.
        def card_link?(link)
          (@card_links ||= {}.compare_by_identity).fetch(link) do
            @card_links[link] = link.find(&:heading?) && link.find { |node| node.link? && !node.equal?(link) }.nil?
          end
        end

        # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def candidate_facts(anchor, container)
          destination = @link_resolver.destination_facts(anchor)
          return unless destination

          text = anchor.visible_text.to_s.strip
          heading = first_heading(container)
          heading_text = heading ? heading.visible_text.to_s.strip : ''
          meaningful = text.match?(/\p{Alnum}/)
          heading_anchor = heading_anchor?(anchor, heading) || (!meaningful && overlay_link?(anchor, heading))
          content_like = destination.content_path
          heading_match = meaningful && heading_text.match?(/\p{Alnum}/) && heading_text == text

          return if @noise_policy.noise_anchor?(
            text:, destination_facts: destination, anchor:, container:, heading_anchor:,
            utility_landmark_ancestor: @segmenter.landmark_ancestor?(anchor, container)
          )
          return unless meaningful || content_like || heading_anchor

          score = (heading_anchor ? 100 : 0) +
                  (heading_match ? 20 : 0) +
                  (meaningful ? 10 : 0) +
                  (content_like ? 10 : 0)

          { anchor:, destination: destination.destination, score: }
        end

        def first_heading(container)
          (@headings ||= {}.compare_by_identity)[container] ||= container.find(&:heading?)
        end

        def heading_anchor?(anchor, heading)
          return false unless heading

          anchor.equal?(heading) || @index.descendant_of?(anchor, heading)
        end

        # An empty overlay link beside the heading (or a wrapper of it) stands in for the heading's link.
        def overlay_link?(anchor, heading)
          return false unless heading&.visible_text.to_s.match?(/\p{Alnum}/)

          @index.descendant_of?(heading, @index.parent_of(anchor))
        end
      end
    end
  end
end
