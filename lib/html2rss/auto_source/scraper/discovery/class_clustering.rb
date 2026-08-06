# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      module Discovery
        ##
        # ClassClustering clusters DOM elements on anchorless pages by class lists and scores
        # candidate groups to find the best list of content cards/articles.
        class ClassClustering
          # Node tags considered layout containers
          LAYOUT_TAG_NAMES = Set['div', 'section', 'article', 'li', 'ul', 'ol'].freeze
          # HTML/layout tags excluded from candidate nodes
          EXCLUDED_TAGS = Set['html', 'body', 'nav', 'footer', 'header', 'svg', 'script', 'style'].freeze

          class << self
            ##
            # Clusters elements in parsed_body and returns the best set of content card nodes.
            #
            # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
            # @param minimum_selector_frequency [Integer] minimum frequency for class groups
            # @return [Array<Nokogiri::XML::Node>] candidate nodes of the top-scoring class group
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

            scorer = GroupScorer.new
            resolver = OverlapResolver.new(layout_tags: LAYOUT_TAG_NAMES, word_counter: scorer)

            non_containers = resolver.filter_containers(candidate_groups)
            final_groups = resolver.filter_1_to_1_overlap(non_containers)

            scorer.select_best_group(final_groups)
          end

          private

          def collect_candidate_groups
            class_groups = Hash.new { |h, k| h[k] = [] }
            cache = {}.compare_by_identity

            @parsed_body.css('[class]').each { |node| add_node_to_groups(node, class_groups, cache) }

            class_groups.select { |_, nodes| nodes.size >= @minimum_frequency }
          end

          def add_node_to_groups(node, class_groups, cache)
            return if EXCLUDED_TAGS.include?(node.name)
            return if Html2rss::Html::Navigator.ignored_container_path?(node, cache)

            cls = normalize_class(node['class'])
            class_groups[cls] << node unless cls.empty?
          end

          def normalize_class(class_attr)
            class_str = class_attr.to_s.strip
            return '' if class_str.empty?

            # Bypass split/sort/join allocation for single-class lists
            if class_str.include?(' ')
              class_str.split(/\s+/).sort.join(' ')
            else
              class_str
            end
          end
        end
      end
    end
  end
end
