# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Discovery
      ##
      # StructureClustering clusters DOM elements on anchorless pages by 1-level child element tag sequences
      # and scores candidate groups to find the best list of content cards/articles when class clustering fails.
      class StructureClustering
        # Node tags considered layout containers
        LAYOUT_TAG_NAMES = ClassClustering::LAYOUT_TAG_NAMES
        # HTML/layout tags excluded from candidate nodes (owned by Html::Navigator).
        EXCLUDED_TAGS = Html2rss::Html::Navigator::CLUSTER_EXCLUDED_TAGS

        class << self
          ##
          # Clusters elements in parsed_body by structural tag signature and returns candidate nodes.
          #
          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @param minimum_selector_frequency [Integer] minimum frequency for structural groups
          # @return [Array<Nokogiri::XML::Node>] candidate nodes of the top-scoring structural group
          def call(parsed_body, minimum_selector_frequency:)
            new(parsed_body, minimum_selector_frequency:).call
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document]
        # @param minimum_selector_frequency [Integer]
        def initialize(parsed_body, minimum_selector_frequency:)
          @parsed_body = parsed_body
          @minimum_frequency = minimum_selector_frequency
        end

        # @return [Array<Nokogiri::XML::Node>]
        def call
          candidate_groups = collect_candidate_groups
          return [] if candidate_groups.empty?

          score_candidate_groups(candidate_groups)
        end

        private

        def score_candidate_groups(candidate_groups)
          scorer = ClassClustering::GroupScorer.new
          resolver = ClassClustering::OverlapResolver.new(layout_tags: LAYOUT_TAG_NAMES, word_counter: scorer)

          non_containers = resolver.filter_containers(candidate_groups)
          final_groups = resolver.filter_1_to_1_overlap(non_containers)

          scorer.select_best_group(final_groups)
        end

        def collect_candidate_groups
          structure_groups = Hash.new { |h, k| h[k] = [] }
          cache = {}.compare_by_identity

          @parsed_body.xpath('//*').each { |node| add_node_to_groups(node, structure_groups, cache) }

          structure_groups.select { |_, nodes| nodes.size >= @minimum_frequency }
        end

        def add_node_to_groups(node, structure_groups, cache)
          return if EXCLUDED_TAGS.include?(node.name)
          return if Html2rss::Html::Navigator.ignored_container_path?(node, cache)

          sig = structure_signature(node)
          structure_groups[sig] << node unless sig.empty?
        end

        def structure_signature(node)
          child_tags = node.children.select(&:element?).map(&:name)
          return '' if child_tags.empty?

          child_tags.join('>')
        end
      end
    end
  end
end
