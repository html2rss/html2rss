# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Builds repeated-list article segments from tag_path frequency
      # (port of Discovery::ListCandidates using tag_path instead of xpath).
      module List
        module_function

        ##
        # @param segmenter [Segmenter]
        # @return [Array<Segment>]
        def call(segmenter)
          primary = PrimaryLink.new(segmenter)
          pairs = article_pairs(segmenter)
          seen = Set.new

          pairs.each_with_index.filter_map do |(article_tag, selected_anchor), position|
            next unless seen.add?(article_tag)

            link = selected_anchor || primary.select(article_tag)
            next unless link || segmenter.permit_unanchored

            Segment.build(root_node: article_tag, primary_link: link, strategy: :list, position:)
          end
        end

        def article_pairs(segmenter)
          selectors(segmenter).flat_map do |path|
            article_pairs_for_path(segmenter, path)
          end
        end
        module_function :article_pairs
        private_class_method :article_pairs

        def article_pairs_for_path(segmenter, path)
          segmenter.index.each_node.filter_map do |node|
            next unless node.link?
            next unless node.tag_path == path
            next if segmenter.index.ignored_chrome?(node)
            next unless relevant_anchor?(segmenter, node)

            article_tag = parent_until_boundary(segmenter, node)
            next unless article_tag

            [article_tag, node]
          end
        end
        module_function :article_pairs_for_path
        private_class_method :article_pairs_for_path

        def selectors(segmenter)
          counts = Hash.new(0)
          segmenter.index.each_node do |node|
            next unless node.link?
            next if segmenter.index.ignored_chrome?(node)
            next unless relevant_anchor?(segmenter, node)

            counts[node.tag_path] += 1
          end

          counts.select { |_path, count| count >= segmenter.minimum_selector_frequency }
                .max_by(segmenter.use_top_selectors, &:last)
                .map(&:first)
        end
        module_function :selectors
        private_class_method :selectors

        def relevant_anchor?(segmenter, node)
          facts = segmenter.link_resolver.destination_facts(node)
          return false unless facts

          text = node.visible_text.to_s.strip
          !segmenter.noise_policy.noise_anchor?(text:, destination_facts: facts, anchor: node)
        end
        module_function :relevant_anchor?
        private_class_method :relevant_anchor?

        def parent_until_boundary(segmenter, node)
          index = segmenter.index
          anchor_counts = Hash.new { |h, n| h[n] = count_links(n) }

          index.parent_until(node, lambda { |curr|
            return true if %i[body html].include?(curr.name)
            return false if index.ignored_chrome?(curr)

            parent = index.parent_of(curr)
            parent && anchor_counts[parent] > anchor_counts[curr]
          })
        end
        module_function :parent_until_boundary
        private_class_method :parent_until_boundary

        def count_links(node)
          node.link? ? 1 : node.descendants.count(&:link?)
        end
        module_function :count_links
        private_class_method :count_links
      end
    end
  end
end
