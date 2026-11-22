# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      module Semantic
        ##
        # Single O(N) post-order pass marking the candidate containers that hold a same-name candidate
        # (wrappers, not leaf cards), except a card div.
        class NonLeaf
          TAG_MASKS = { article: 1, section: 2, li: 4, tr: 8, div: 16 }.freeze
          private_constant :TAG_MASKS

          ##
          # @param root [SST::Node]
          # @return [Set<SST::Node>] marked nodes, compared by identity
          def self.call(root) = new.call(root)

          def initialize
            @marked = Set.new.compare_by_identity
          end

          # @param root [SST::Node]
          # @return [Set<SST::Node>]
          def call(root)
            visit(root)
            @marked
          end

          private

          # @return [Array(Integer, Integer, Boolean)] tag mask strictly below, headings in the subtree,
          #   whether a div strictly below holds a heading
          def visit(node) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            seen_mask = 0
            headings = node.heading? ? 1 : 0
            div_heading = false
            node.children.each do |child|
              child_mask, child_headings, child_div_heading = visit(child)
              seen_mask |= child_mask | TAG_MASKS.fetch(child.name, 0)
              headings += child_headings
              div_heading ||= child_div_heading || (child.name == :div && child_headings.positive?)
            end
            @marked.add(node) if non_leaf?(node, seen_mask, headings, div_heading)
            [seen_mask, headings, div_heading]
          end

          def non_leaf?(node, seen_mask, headings, div_heading)
            mask = TAG_MASKS[node.name]
            mask && seen_mask.anybits?(mask) && !card_div?(node, headings, div_heading)
          end

          # A div holding one linked heading, no heading in its inner divs, and mostly links to the
          # heading's destination is a card: its inner divs are info blocks (time, tag chips), not
          # cards. A section wrapper fails the link test: its heading links an index, its body others.
          def card_div?(node, headings, div_heading)
            node.name == :div && headings == 1 && !div_heading && mostly_one_destination?(node)
          end

          def mostly_one_destination?(node)
            href = node.find(&:heading?).find(&:link?)&.attrs&.href
            return false unless href

            links = node.find_all(&:link?)
            links.count { _1.attrs.href == href } * 2 >= links.size
          end
        end
      end
    end
  end
end
