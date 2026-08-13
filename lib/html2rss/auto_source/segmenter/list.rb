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
          seen = {}.compare_by_identity

          pairs.each_with_index.filter_map do |(article_tag, selected_anchor), position|
            next unless seen[article_tag].nil?

            seen[article_tag] = true

            link = selected_anchor || primary.select(article_tag)
            next unless link || segmenter.permit_unanchored

            Segment.build(root_node: article_tag, primary_link: link, strategy: :list, position:)
          end
        end

        def article_pairs(segmenter)
          by_path = relevant_links_by_path(segmenter)
          top_paths(segmenter, by_path).flat_map do |path|
            by_path.fetch(path, []).filter_map do |node|
              article_tag = parent_until_boundary(segmenter, node)
              next unless article_tag

              [article_tag, node]
            end
          end
        end
        module_function :article_pairs
        private_class_method :article_pairs

        def relevant_links_by_path(segmenter)
          by_path = Hash.new { |hash, path| hash[path] = [] }
          segmenter.index.each_node do |node|
            next unless node.link?
            next if segmenter.index.ignored_chrome?(node)
            next unless relevant_anchor?(segmenter, node)

            by_path[node.tag_path] << node
          end
          by_path
        end
        module_function :relevant_links_by_path
        private_class_method :relevant_links_by_path

        def top_paths(segmenter, by_path)
          by_path.select { |_path, nodes| nodes.size >= segmenter.minimum_selector_frequency }
                .max_by(segmenter.use_top_selectors) { |_path, nodes| nodes.size }
                .map(&:first)
        end
        module_function :top_paths
        private_class_method :top_paths

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
          link_counts = Hash.new { |hash, curr| hash[curr] = count_links(curr) }

          index.parent_until(node, lambda { |curr|
            return true if %i[body html].include?(curr.name)
            return false if index.ignored_chrome?(curr)

            parent = index.parent_of(curr)
            parent && link_counts[parent] > link_counts[curr]
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
