# frozen_string_literal: true

module Html2rss
  class AutoSource
    class Segmenter
      ##
      # Collects leaf semantic containers (port of Discovery::SemanticContainers).
      module Semantic
        # Tag names collected as leaf semantic containers.
        CANDIDATE_NAMES = %i[article section li tr div].to_set.freeze

        ##
        # @param segmenter [Segmenter]
        # @return [Array<Segment>]
        def self.call(segmenter)
          picks = linked_containers(segmenter)
          # A link wrapping its container is a whole card: it roots one segment, not one per div inside
          # it, and none when a container already selected that link from inside.
          claimed = picks.filter_map { |_, link, inside| link if inside }.to_set.compare_by_identity

          roots = picks.each_with_index.filter_map do |(container, link, inside), position|
            root = inside ? container : (link if claimed.add?(link))
            [root, link, position] if root
          end
          build_segments(roots, segmenter)
        end

        # Each segment carries the size of its repeated-card group: the cards of main content that share
        # its structural path (see {card_path}). A card in a peripheral landmark (aside) or one linking an
        # audio or video destination (video, podcast) joins no group, and counts for none.
        def self.build_segments(roots, segmenter)
          index = segmenter.index
          paths = roots.map { |root, link, _| groupable?(root, link, segmenter) && card_path(root, index) }
          sizes = paths.tally
          roots.zip(paths).map do |(root, link, position), path|
            Segment.build(root_node: root, primary_link: link, strategy: :semantic, position:,
                          group_size: path ? sizes.fetch(path) : 1)
          end
        end
        private_class_method :build_segments

        def self.groupable?(root, link, segmenter)
          !segmenter.index.peripheral?(root) && !segmenter.link_resolver.destination_facts(link).media_path
        end
        private_class_method :groupable?

        # A card's structural path: the tag and folded class tokens of the card and of each ancestor.
        # Cards of one list share it, also when the list is split over repeated rows or columns; a
        # sidebar rail or a topical module sits under other markup and does not, however prominent
        # each of its items is.
        def self.card_path(root, index)
          path = []
          node = root
          while node
            path << [node.name, Cluster.normalize_class(node.attrs.class_names)]
            node = index.parent_of(node)
          end
          path
        end
        private_class_method :card_path

        # @return [Array<Array(SST::Node, SST::Node, Boolean)>] container, its primary link, link inside it
        def self.linked_containers(segmenter)
          index = segmenter.index
          primary = PrimaryLink.new(segmenter)
          collect_containers(index).filter_map do |container|
            link = primary.select(container)
            [container, link, index.descendant_of?(link, container)] if link
          end
        end
        private_class_method :linked_containers

        def self.collect_containers(index)
          non_leaf = NonLeaf.call(index.root)
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
        private_class_method :collect_containers

        def self.filter_nested(candidates, index)
          candidate_set = {}.compare_by_identity
          candidates.each { |c| candidate_set[c] = true }
          rejected = {}.compare_by_identity

          candidates.each do |candidate|
            next if candidate.name == :div

            reject_ancestors(candidate, candidate_set, rejected, index)
          end

          candidates.reject { |c| rejected[c] }
        end
        private_class_method :filter_nested

        def self.reject_ancestors(node, candidate_set, rejected, index)
          curr = index.parent_of(node)
          while curr && curr.name != :html
            rejected[curr] = true if candidate_set[curr]
            curr = index.parent_of(curr)
          end
        end
        private_class_method :reject_ancestors

        def self.sort_by_depth(candidates, index)
          candidates.each_with_index
                    .sort_by { |node, i| [-index.depth_of(node), i] }
                    .map(&:first)
        end
        private_class_method :sort_by_depth
      end
    end
  end
end
