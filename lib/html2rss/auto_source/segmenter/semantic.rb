# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Collects leaf semantic containers (port of Discovery::SemanticContainers).
      module Semantic
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
          candidates = index.each_node.select do |node|
            CANDIDATE_NAMES.include?(node.name) &&
              node.leaf_semantic_candidate? &&
              !index.ignored_chrome?(node)
          end

          candidates = filter_nested(candidates, index)
          sort_by_depth(candidates, index)
        end
        module_function :collect_containers
        private_class_method :collect_containers

        def filter_nested(candidates, index)
          candidate_set = Set.new(candidates)
          rejected = Set.new

          candidates.each do |candidate|
            next if candidate.name == :div

            reject_ancestors(candidate, candidate_set, rejected, index)
          end

          candidates.reject { |c| rejected.include?(c) }
        end
        module_function :filter_nested
        private_class_method :filter_nested

        def reject_ancestors(node, candidate_set, rejected, index)
          curr = index.parent_of(node)
          while curr && curr.name != :html
            rejected << curr if candidate_set.include?(curr)
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
