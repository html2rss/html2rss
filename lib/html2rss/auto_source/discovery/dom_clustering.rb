# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Discovery
      ##
      # Discovers repeated content card nodes in anchorless or classless DOM trees
      # by evaluating class groups first and falling back to 1-level tag structure signatures.
      class DomClustering
        # Node tags considered layout containers
        LAYOUT_TAG_NAMES = Set['div', 'section', 'article', 'li', 'ul', 'ol'].freeze
        # HTML/layout tags excluded from candidate nodes (owned by Html::Navigator).
        EXCLUDED_TAGS = Html2rss::Html::Navigator::CLUSTER_EXCLUDED_TAGS

        class << self
          ##
          # Clusters elements in parsed_body and returns the best set of content card nodes.
          #
          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @param minimum_selector_frequency [Integer] minimum frequency for candidate groups
          # @return [Array<Nokogiri::XML::Node>] candidate nodes of the top-scoring cluster
          def call(parsed_body, minimum_selector_frequency:)
            new(parsed_body, minimum_frequency: minimum_selector_frequency).call
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document]
        # @param minimum_frequency [Integer]
        def initialize(parsed_body, minimum_frequency:)
          @parsed_body = parsed_body
          @minimum_frequency = minimum_frequency
          @cache = {}.compare_by_identity
        end

        # @return [Array<Nokogiri::XML::Node>]
        def call
          class_result = cluster_by_class
          return class_result unless class_result.empty?

          cluster_by_structure
        end

        private

        attr_reader :parsed_body, :minimum_frequency, :cache

        def cluster_by_class
          class_groups = collect_class_groups
          return [] if class_groups.empty?

          score_groups(class_groups)
        end

        def cluster_by_structure
          structure_groups = collect_structure_groups
          return [] if structure_groups.empty?

          score_groups(structure_groups)
        end

        def score_groups(candidate_groups)
          scorer = GroupScorer.new
          resolver = OverlapResolver.new(layout_tags: LAYOUT_TAG_NAMES, word_counter: scorer)

          non_containers = resolver.filter_containers(candidate_groups)
          final_groups = resolver.filter_1_to_1_overlap(non_containers)

          scorer.select_best_group(final_groups)
        end

        def collect_class_groups
          groups = Hash.new { |h, k| h[k] = [] }
          parsed_body.css('[class]').each { |node| add_class_node(node, groups) }
          groups.select { |_, nodes| nodes.size >= minimum_frequency }
        end

        def add_class_node(node, groups)
          return if EXCLUDED_TAGS.include?(node.name)
          return if Html2rss::Html::Navigator.ignored_container_path?(node, cache)

          cls = normalize_class(node['class'])
          groups[cls] << node unless cls.empty?
        end

        def collect_structure_groups
          groups = Hash.new { |h, k| h[k] = [] }
          parsed_body.xpath('//*').each { |node| add_structure_node(node, groups) }
          groups.select { |_, nodes| nodes.size >= minimum_frequency }
        end

        def add_structure_node(node, groups)
          return if EXCLUDED_TAGS.include?(node.name)
          return if Html2rss::Html::Navigator.ignored_container_path?(node, cache)

          sig = structure_signature(node)
          groups[sig] << node unless sig.empty?
        end

        def normalize_class(class_attr)
          class_str = class_attr.to_s.strip
          return '' if class_str.empty?

          if class_str.include?(' ')
            class_str.split(/\s+/).sort.join(' ')
          else
            class_str
          end
        end

        def structure_signature(node)
          child_elements = node.element_children
          return '' if child_elements.empty?

          child_elements.map(&:name).join('>')
        end
      end
    end
  end
end
