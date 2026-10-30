# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Builds repeated-list article segments by grouping cards under a shared parent.
      # When the document has a +main+ or +[role=main]+, anchors outside it are dropped.
      module List
        ##
        # @param segmenter [Segmenter]
        # @return [Array<Segment>]
        def self.call(segmenter)
          article_pairs(segmenter).each_with_index.map do |(article_tag, link), position|
            Segment.build(root_node: article_tag, primary_link: link, strategy: :list, position:)
          end
        end

        def self.article_pairs(segmenter)
          top_groups(segmenter).flatten(1)
        end
        private_class_method :article_pairs

        def self.top_groups(segmenter)
          cards_by_parent(segmenter)
            .select { |_parent, cards| cards.size >= segmenter.minimum_selector_frequency }
            .max_by(segmenter.use_top_selectors) { |_parent, cards| cards.size }
            .map(&:last)
        end
        private_class_method :top_groups

        def self.cards_by_parent(segmenter)
          index = segmenter.index
          main = main_landmark(index)
          groups = {}.compare_by_identity

          index.each_node.select { |node| card_anchor?(segmenter, index, main, node) }.each do |node|
            card = parent_until_boundary(segmenter, node)
            (groups[index.parent_of(card)] ||= []) << [card, node]
          end
          groups
        end
        private_class_method :cards_by_parent

        def self.card_anchor?(segmenter, index, main, node)
          node.link? && !index.ignored_chrome?(node) && relevant_anchor?(segmenter, node) &&
            (main.nil? || inside_main?(index, node, main))
        end
        private_class_method :card_anchor?

        def self.main_landmark(index)
          index.each_node.find { |node| node.name == :main || node.attrs.raw['role'] == 'main' }
        end
        private_class_method :main_landmark

        def self.inside_main?(index, node, main)
          node.equal?(main) || index.descendant_of?(node, main)
        end
        private_class_method :inside_main?

        def self.relevant_anchor?(segmenter, node)
          !segmenter.noise_policy.noise_anchor?(
            text: node.visible_text, destination_facts: segmenter.link_resolver.destination_facts(node),
            anchor: node
          )
        end
        private_class_method :relevant_anchor?

        BOUNDARY_TAGS = Set[:body, :html].freeze
        private_constant :BOUNDARY_TAGS

        def self.parent_until_boundary(segmenter, node)
          index = segmenter.index
          link_counts = Hash.new { |hash, curr| hash[curr] = count_relevant_links(segmenter, curr) }

          index.parent_until(node, lambda { |curr|
            return true if BOUNDARY_TAGS.include?(curr.name)

            link_counts[index.parent_of(curr)] > link_counts[curr]
          })
        end
        private_class_method :parent_until_boundary

        # Walk nodes are relevant anchors or their non-link ancestors, so a link counts as one.
        def self.count_relevant_links(segmenter, node)
          return 1 if node.link?

          node.count_descendants { |child| child.link? && relevant_anchor?(segmenter, child) }
        end
        private_class_method :count_relevant_links
      end
    end
  end
end
