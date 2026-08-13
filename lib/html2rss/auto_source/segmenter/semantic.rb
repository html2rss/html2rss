# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Collects leaf semantic containers (port of Discovery::SemanticContainers).
      module Semantic
        # Tag names collected as leaf semantic containers.
        CANDIDATE_NAMES = %i[article section li tr div].to_set.freeze

        module_function

        ##
        # @param segmenter [Segmenter]
        # @return [Array<Segment>]
        def call(segmenter)
          containers = collect_containers(segmenter.index)
          primary = PrimaryLink.new(segmenter)

          containers.each_with_index.filter_map do |container, position|
            link = primary.select(container)
            next unless link || segmenter.permit_unanchored

            Segment.build(root_node: container, primary_link: link, strategy: :semantic, position:)
          end
        end

        def collect_containers(index)
          non_leaf = mark_non_leaf_candidates(index.root)
          candidates = []
          index.each_node do |node|
            next unless CANDIDATE_NAMES.include?(node.name)
            next if non_leaf.include?(node)
            next if index.ignored_chrome?(node)

            candidates << node
          end

          candidates = filter_nested(candidates, index)
          sort_by_depth(candidates, index)
        end
        module_function :collect_containers
        private_class_method :collect_containers

        # Single O(N) post-order pass: mark candidate nodes that contain a same-name candidate.
        def mark_non_leaf_candidates(root) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          non_leaf = Set.new.compare_by_identity
          visit = lambda do |node|
            seen = Hash.new(false)
            node.children.each do |child|
              child_seen = visit.call(child)
              child_seen.each_key { |name| seen[name] = true }
              seen[child.name] = true if CANDIDATE_NAMES.include?(child.name)
            end
            non_leaf.add(node) if CANDIDATE_NAMES.include?(node.name) && seen[node.name]
            seen
          end
          visit.call(root)
          non_leaf
        end
        module_function :mark_non_leaf_candidates
        private_class_method :mark_non_leaf_candidates

        def filter_nested(candidates, index)
          candidate_set = {}.compare_by_identity
          candidates.each { |c| candidate_set[c] = true }
          rejected = {}.compare_by_identity

          candidates.each do |candidate|
            next if candidate.name == :div

            reject_ancestors(candidate, candidate_set, rejected, index)
          end

          candidates.reject { |c| rejected[c] }
        end
        module_function :filter_nested
        private_class_method :filter_nested

        def reject_ancestors(node, candidate_set, rejected, index)
          curr = index.parent_of(node)
          while curr && curr.name != :html
            rejected[curr] = true if candidate_set[curr]
            curr = index.parent_of(curr)
          end
        end
        module_function :reject_ancestors
        private_class_method :reject_ancestors

        def sort_by_depth(candidates, index)
          candidates.each_with_index
                    .sort_by { |node, i| [-index.depth_of(node), i] }
                    .map(&:first)
        end
        module_function :sort_by_depth
        private_class_method :sort_by_depth
      end
    end
  end
end
