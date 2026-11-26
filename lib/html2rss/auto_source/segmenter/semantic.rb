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

          # Claiming runs deepest first; segments and their position follow document order.
          roots = picks.filter_map do |container, link, inside, position|
            root = inside ? container : (link if claimed.add?(link))
            [root, link, position] if root
          end
          build_segments(roots, segmenter)
        end

        # A container whose payload (text, image, video, date) lies wholly inside several cards, each owning its own
        # headline link (a link wrapping a heading, or a heading wrapping a link), is a run of cards, not one card:
        # each link roots its segment itself, so neighbouring cards stay out of its text. A card with loose payload
        # beside a second headline link, such as a related story, stays one card.
        def self.card_run?(node)
          cards = card_units(node)
          node.visible_text(exclude: cards).to_s.empty? && payload_count(node) == cards.sum { payload_count(_1) }
        end
        private_class_method :card_run?

        # The nodes below +node+ that each own headline links, descending through a lone wrapper.
        def self.card_units(node)
          holders = node.children.select { |child| headline_links?(child) }
          holders.size == 1 ? card_units(holders.first) : holders
        end
        private_class_method :card_units

        def self.headline_links?(node)
          return node.find(&:link?) if node.heading?

          node.link? ? node.find(&:heading?) : node.children.any? { |child| headline_links?(child) }
        end
        private_class_method :headline_links?

        def self.payload_count(node)
          node.each_node.count { |n| AutoSource::ArticleRules::Image.carrier?(n) || n.name == :video || n.attrs.datetime }
        end
        private_class_method :payload_count

        # Each segment carries the size of its repeated-card group: the cards of main content that share
        # its structural path (see {card_path}). A card in a peripheral landmark (aside) or one linking an
        # audio or video destination (video, podcast) joins no group, and counts for none.
        def self.build_segments(roots, segmenter)
          index = segmenter.index
          roots = roots.sort_by(&:last)
          paths = roots.map { |root, link, _| groupable?(root, link, segmenter) && card_path(root, index) }
          sizes = paths.tally
          roots.zip(paths).map do |(root, link, position), path|
            Segment.build(root_node: root, primary_link: link, strategy: :semantic, position:,
                          group_size: path ? sizes.fetch(path) : 1)
          end
        end
        private_class_method :build_segments

        def self.groupable?(root, link, segmenter)
          !segmenter.index.peripheral?(root) && !segmenter.link_resolver.destination_facts(link)&.media_path
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

        # @return [Array<Array(Html::SST::Node, Html::SST::Node, Boolean, Integer)>] container, primary link, roots
        #   the card (the link sits inside it and it is not a run of cards), container's document position;
        #   deepest container first
        def self.linked_containers(segmenter)
          index = segmenter.index
          primary = PrimaryLink.new(segmenter)
          collect_containers(index).filter_map do |container, position|
            link = primary.select(container)
            [container, link, index.descendant_of?(link, container) && !card_run?(container), position] if link
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
          candidates.each_with_index.sort_by { |node, i| [-index.depth_of(node), i] }
        end
        private_class_method :sort_by_depth
      end
    end
  end
end
