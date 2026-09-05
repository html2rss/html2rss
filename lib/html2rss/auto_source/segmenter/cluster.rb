# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Class / structure clustering for anchorless pages
      # (port of Discovery::DomClustering + OverlapResolver; group scoring owned by Scoring::ClusterScorer).
      module Cluster
        module_function

        ##
        # @param segmenter [Segmenter]
        # @return [Array<Segment>]
        def call(segmenter)
          nodes = best_group_nodes(segmenter)
          nodes.each_with_index.map do |node, position|
            Segment.build(root_node: node, primary_link: nil, strategy: :cluster, position:)
          end
        end

        def best_group_nodes(segmenter)
          class_groups = collect_class_groups(segmenter)
          groups = class_groups.empty? ? collect_structure_groups(segmenter) : class_groups
          return [] if groups.empty?

          resolver = OverlapResolver.new(index: segmenter.index)
          scorer = Scoring::ClusterScorer.new
          non_containers = resolver.filter_containers(groups)
          final_groups = resolver.filter_1_to_1_overlap(non_containers)
          scorer.select_best_group(final_groups)
        end
        module_function :best_group_nodes
        private_class_method :best_group_nodes

        def collect_class_groups(segmenter) # rubocop:disable Metrics/AbcSize
          groups = Hash.new { |h, k| h[k] = [] }
          segmenter.index.each_node do |node|
            next if SST::Tags::CLUSTER_EXCLUDED_NAMES.include?(node.name)
            next if segmenter.index.ignored_chrome?(node)

            cls = normalize_class(node.attrs.class_names)
            groups[cls] << node unless cls.empty?
          end
          groups.select { |_, nodes| nodes.size >= segmenter.minimum_selector_frequency }
        end
        module_function :collect_class_groups
        private_class_method :collect_class_groups

        def collect_structure_groups(segmenter) # rubocop:disable Metrics/AbcSize
          groups = Hash.new { |h, k| h[k] = [] }
          segmenter.index.each_node do |node|
            next if SST::Tags::CLUSTER_EXCLUDED_NAMES.include?(node.name)
            next if segmenter.index.ignored_chrome?(node)

            sig = structure_signature(node)
            groups[sig] << node unless sig.empty?
          end
          groups.select { |_, nodes| nodes.size >= segmenter.minimum_selector_frequency }
        end
        module_function :collect_structure_groups
        private_class_method :collect_structure_groups

        def normalize_class(class_names)
          return '' if class_names.empty?

          class_names.map { ::Html2rss::Html::Probe.fold(_1) }.sort.join(' ')
        end
        module_function :normalize_class
        private_class_method :normalize_class

        def structure_signature(node)
          kids = node.children
          return '' if kids.empty?

          kids.map { |c| c.name.to_s }.join('>')
        end
        module_function :structure_signature
        private_class_method :structure_signature

        ##
        # Filters layout wrapper groups and resolves 1-to-1 nested card wrappers.
        class OverlapResolver
          # Cap pairwise work on dense class grids.
          MAX_GROUPS = 40

          # @param index [SST::Index]
          def initialize(index:)
            @index = index
            @layout_tags = SST::Tags::LAYOUT_NAMES
            @scorer = Scoring::ClusterScorer.new
          end

          # @param groups [Hash{String => Array<SST::Node>}]
          # @return [Hash{String => Array<SST::Node>}]
          def filter_containers(groups)
            capped = cap_groups(groups)
            capped.reject do |cls_a, nodes_a|
              capped.any? { |cls_b, nodes_b| cls_a != cls_b && container_of?(nodes_a, nodes_b) }
            end
          end

          # @param groups [Hash{String => Array<SST::Node>}]
          # @return [Hash{String => Array<SST::Node>}]
          def filter_1_to_1_overlap(groups)
            discarded = {}
            groups.each_key do |cls_a|
              groups.each_key do |cls_b|
                next if cls_a == cls_b || discarded[cls_a] || discarded[cls_b]

                resolve_1_to_1_overlap(cls_a, cls_b, groups, discarded)
              end
            end
            groups.reject { |cls, _| discarded[cls] }
          end

          private

          def cap_groups(groups)
            return groups if groups.size <= MAX_GROUPS

            groups.sort_by { |_key, nodes| -nodes.size }.first(MAX_GROUPS).to_h
          end

          # rubocop:disable-next Metrics/MethodLength
          def container_of?(nodes_a, nodes_b)
            return false unless @layout_tags.include?(nodes_b.first.name)

            nodes_a.any? do |node_a|
              count = 0
              nodes_b.each do |node_b|
                next if node_a.equal?(node_b)

                if @index.descendant_of?(node_b, node_a)
                  count += 1
                  break if count > 1
                end
              end
              count > 1
            end
          end

          def resolve_1_to_1_overlap(cls_a, cls_b, groups, discarded)
            nodes_a = groups[cls_a]
            nodes_b = groups[cls_b]
            return if nodes_a.size != nodes_b.size

            nested = nodes_a.zip(nodes_b).all? { |a, b| !a.equal?(b) && @index.descendant_of?(b, a) }
            return unless nested

            discarded[keep_descendant?(nodes_a, nodes_b) ? cls_a : cls_b] = true
          end

          def keep_descendant?(nodes_a, nodes_b)
            @scorer.avg_words(nodes_b) >= 0.8 * @scorer.avg_words(nodes_a) &&
              @layout_tags.include?(nodes_b.first.name)
          end
        end
      end
    end
  end
end
