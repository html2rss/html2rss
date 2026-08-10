# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Discovery
      class ClassClustering
        ##
        # Filters layout wrapper groups and resolves 1-to-1 nested card wrappers.
        class OverlapResolver
          # @param layout_tags [Set<String>] tags treated as layout containers
          # @param word_counter [#avg_words] averages visible word counts for nodes
          def initialize(layout_tags:, word_counter:)
            @layout_tags = layout_tags
            @word_counter = word_counter
          end

          # Discard group A if any node of A contains > 1 node of another group B
          #
          # @param groups [Hash{String => Array<Nokogiri::XML::Node>}] class groups
          # @return [Hash{String => Array<Nokogiri::XML::Node>}] groups that are not layout wrappers
          def filter_containers(groups)
            groups.reject do |cls_a, nodes_a|
              groups.any? { |cls_b, nodes_b| cls_a != cls_b && container_of?(nodes_a, nodes_b) }
            end
          end

          # If group A contains group B with the same size, keep the real content card.
          #
          # @param groups [Hash{String => Array<Nokogiri::XML::Node>}] class groups
          # @return [Hash{String => Array<Nokogiri::XML::Node>}] groups after 1-to-1 resolution
          def filter_1_to_1_overlap(groups)
            discarded = Set.new
            groups.each_key do |cls_a|
              groups.each_key do |cls_b|
                next if cls_a == cls_b || discarded.include?(cls_a) || discarded.include?(cls_b)

                resolve_1_to_1_overlap(cls_a, cls_b, groups, discarded)
              end
            end

            groups.except(*discarded)
          end

          private

          attr_reader :layout_tags, :word_counter

          # rubocop:disable Metrics/MethodLength
          def container_of?(nodes_a, nodes_b)
            return false unless layout_tags.include?(nodes_b.first.name)

            nodes_a.any? do |node_a|
              count = 0
              nodes_b.each do |node_b|
                next if node_a == node_b

                if Html2rss::Html::Navigator.descendant_of?(node_b, node_a)
                  count += 1
                  break if count > 1
                end
              end
              count > 1
            end
          end
          # rubocop:enable Metrics/MethodLength

          def resolve_1_to_1_overlap(cls_a, cls_b, groups, discarded)
            nodes_a = groups[cls_a]
            nodes_b = groups[cls_b]
            return if nodes_a.size != nodes_b.size

            nested = nodes_a.zip(nodes_b).all? { |a, b| a != b && Html2rss::Html::Navigator.descendant_of?(b, a) }
            return unless nested

            discarded << (keep_descendant?(nodes_a, nodes_b) ? cls_a : cls_b)
          end

          def keep_descendant?(nodes_a, nodes_b)
            word_counter.avg_words(nodes_b) >= 0.8 * word_counter.avg_words(nodes_a) &&
              layout_tags.include?(nodes_b.first.name)
          end
        end
      end
    end
  end
end
