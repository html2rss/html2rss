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
          primary = PrimaryLink.new(segmenter)
          pairs = article_pairs(segmenter)
          seen = {}.compare_by_identity

          pairs.each_with_index.filter_map do |(article_tag, selected_anchor), position|
            next unless seen[article_tag].nil?

            seen[article_tag] = true

            link = selected_anchor || primary.select(article_tag)
            next unless link || segmenter.permit_unanchored

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

        def self.cards_by_parent(segmenter) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          index = segmenter.index
          main = main_landmark(index)
          groups = {}.compare_by_identity

          index.each_node do |node|
            next unless node.link?
            next if index.ignored_chrome?(node)
            next unless relevant_anchor?(segmenter, node)
            next if main && !inside_main?(index, node, main)

            card = parent_until_boundary(segmenter, node)
            next unless card

            parent = index.parent_of(card)
            next unless parent

            (groups[parent] ||= []) << [card, node]
          end
          groups
        end
        private_class_method :cards_by_parent

        def self.main_landmark(index)
          index.each_node.find { |node| node.name == :main || node.attrs.raw['role'] == 'main' }
        end
        private_class_method :main_landmark

        def self.inside_main?(index, node, main)
          node.equal?(main) || index.descendant_of?(node, main)
        end
        private_class_method :inside_main?

        def self.relevant_anchor?(segmenter, node)
          facts = segmenter.link_resolver.destination_facts(node)
          return false unless facts

          text = node.visible_text.to_s.strip
          !segmenter.noise_policy.noise_anchor?(
            text:, destination_facts: facts, anchor: node, utility_landmark_ancestor: false
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
            return false if index.ignored_chrome?(curr)

            parent = index.parent_of(curr)
            parent && link_counts[parent] > link_counts[curr]
          })
        end
        private_class_method :parent_until_boundary

        def self.count_relevant_links(segmenter, node)
          # Chrome inside a card must not stop the walk before the shared list parent.
          if node.link?
            relevant_anchor?(segmenter, node) ? 1 : 0
          else
            node.count_descendants { |child| child.link? && relevant_anchor?(segmenter, child) }
          end
        end
        private_class_method :count_relevant_links
      end
    end
  end
end
