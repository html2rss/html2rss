# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Selects the strongest content-like primary link inside a container
      # (port of Discovery::SemanticAnchorCandidates).
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

          winners.values.max_by { |f| f[:score] }&.fetch(:anchor)
        end

        private

        # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def candidate_facts(anchor, container)
          destination = @link_resolver.destination_facts(anchor)
          return unless destination

          text = anchor.visible_text.to_s.strip
          heading = first_heading(container)
          heading_text = heading ? heading.visible_text.to_s.strip : ''
          heading_anchor = heading_anchor?(anchor, heading)
          meaningful = text.match?(/\p{Alnum}/)
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
      end
    end
  end
end
