# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class Html
        ##
        # ClassClustering clusters DOM elements on anchorless pages by class lists and scores
        # candidate groups to find the best list of content cards/articles.
        class ClassClustering
          # Node tags considered layout containers
          LAYOUT_TAG_NAMES = Set['div', 'section', 'article'].freeze
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
            @text_words = {}.compare_by_identity
            @has_date = {}.compare_by_identity
          end

          # @return [Array<Nokogiri::XML::Node>]
          def call
            candidate_groups = collect_candidate_groups
            return [] if candidate_groups.empty?

            non_containers = filter_containers(candidate_groups)
            final_groups = filter_1_to_1_overlap(non_containers)

            select_best_group(final_groups)
          end

          private

          def collect_candidate_groups
            class_groups = Hash.new { |h, k| h[k] = [] }
            cache = {}.compare_by_identity

            @parsed_body.css('[class]').each do |node|
              next if EXCLUDED_TAGS.include?(node.name)
              next if HtmlExtractor.ignored_container_path?(node, cache)

              cls = normalize_class(node['class'])
              next if cls.empty?

              class_groups[cls] << node
            end

            class_groups.select { |_, nodes| nodes.size >= @minimum_frequency }
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

          # Discard group A if any node of A contains > 1 node of another group B
          def filter_containers(groups)
            groups.reject do |cls_a, nodes_a|
              groups.any? do |cls_b, nodes_b|
                next false if cls_a == cls_b
                next false unless LAYOUT_TAG_NAMES.include?(nodes_b.first.name)

                nodes_a.any? do |node_a|
                  nodes_b.count { |node_b| node_a != node_b && node_b.ancestors.include?(node_a) } > 1
                end
              end
            end
          end

          # If group A contains group B, and they have the same size:
          # - If B (the descendant) contains >= 80% of A's words, AND B's tag is div/section/article,
          #   B is the actual content card. Discard A.
          # - Otherwise, B is a sub-element (header, metadata line, button). Discard B.
          def filter_1_to_1_overlap(groups)
            discarded = Set.new
            groups.each_key do |cls_a|
              groups.each_key do |cls_b|
                next if cls_a == cls_b
                next if discarded.include?(cls_a) || discarded.include?(cls_b)

                nodes_a = groups[cls_a]
                nodes_b = groups[cls_b]
                next if nodes_a.size != nodes_b.size

                # Fast Nokogiri-based 1-to-1 containment walk
                next unless nodes_a.zip(nodes_b).all? { |a, b| a != b && b.ancestors.include?(a) }

                words_a = avg_words(nodes_a)
                words_b = avg_words(nodes_b)

                discarded << if words_b >= 0.8 * words_a && LAYOUT_TAG_NAMES.include?(nodes_b.first.name)
                               cls_a
                             else
                               cls_b
                             end
              end
            end

            groups.reject { |cls, _| discarded.include?(cls) }
          end

          def select_best_group(groups)
            best_nodes = []
            best_score = -1

            groups.each_value do |nodes|
              # Check words threshold for nodes (lazy word count evaluation)
              # Exclude candidate groups with too few words to avoid small structural widgets
              avg_w = avg_words(nodes)
              next if avg_w < 5

              has_heading = nodes.any? { |n| n.at_css(HtmlExtractor::HEADING_TAGS.join(',')) || n.at_css('.font-bold, .font-semibold') }
              has_time = nodes.any? { |n| n.at_css('time, [datetime]') }
              contains_date = nodes.any? { |n| has_date?(n) }

              score = nodes.size + (avg_w / 5.0)
              score += 20 if has_heading
              score += 20 if has_time
              score += 40 if contains_date

              if score > best_score
                best_score = score
                best_nodes = nodes
              end
            end

            best_nodes
          end

          def avg_words(nodes)
            nodes.sum { |n| text_words(n) } / nodes.size.to_f
          end

          def text_words(node)
            @text_words[node] ||= HtmlExtractor.extract_visible_text(node).to_s.scan(/\p{Alnum}+/).size
          end

          def has_date?(node)
            @has_date[node] ||= begin
              text = HtmlExtractor.extract_visible_text(node).to_s
              !!(text.match?(%r{\b\d{4}[-/]\d{2}[-/]\d{2}\b}) || text.match?(/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/i))
            end
          end
        end
      end
    end
  end
end
