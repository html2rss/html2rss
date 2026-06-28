# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class Html
        ##
        # ClassClustering clusters DOM elements on anchorless pages by class lists and scores
        # candidate groups to find the best list of content cards/articles.
        # rubocop:disable Metrics/ClassLength
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

            @parsed_body.css('[class]').each { |node| add_node_to_groups(node, class_groups, cache) }

            class_groups.select { |_, nodes| nodes.size >= @minimum_frequency }
          end

          def add_node_to_groups(node, class_groups, cache)
            return if EXCLUDED_TAGS.include?(node.name) || HtmlExtractor.ignored_container_path?(node, cache)

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

          # Discard group A if any node of A contains > 1 node of another group B
          def filter_containers(groups)
            groups.reject do |cls_a, nodes_a|
              groups.any? { |cls_b, nodes_b| cls_a != cls_b && container_of?(nodes_a, nodes_b) }
            end
          end

          # rubocop:disable Metrics/MethodLength
          def container_of?(nodes_a, nodes_b)
            return false unless LAYOUT_TAG_NAMES.include?(nodes_b.first.name)

            nodes_a.any? do |node_a|
              count = 0
              nodes_b.each do |node_b|
                next if node_a == node_b

                if HtmlNavigator.descendant_of?(node_b, node_a)
                  count += 1
                  break if count > 1
                end
              end
              count > 1
            end
          end
          # rubocop:enable Metrics/MethodLength

          # If group A contains group B, and they have the same size:
          # - If B (the descendant) contains >= 80% of A's words, AND B's tag is div/section/article,
          #   B is the actual content card. Discard A.
          # - Otherwise, B is a sub-element (header, metadata line, button). Discard B.
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

          def resolve_1_to_1_overlap(cls_a, cls_b, groups, discarded)
            nodes_a = groups[cls_a]
            nodes_b = groups[cls_b]
            return if nodes_a.size != nodes_b.size
            return unless nodes_a.zip(nodes_b).all? { |a, b| a != b && HtmlNavigator.descendant_of?(b, a) }

            discarded << (keep_descendant?(nodes_a, nodes_b) ? cls_a : cls_b)
          end

          def keep_descendant?(nodes_a, nodes_b)
            avg_words(nodes_b) >= 0.8 * avg_words(nodes_a) &&
              LAYOUT_TAG_NAMES.include?(nodes_b.first.name)
          end

          def select_best_group(groups)
            best_nodes = []
            best_score = -1

            groups.each_value do |nodes|
              score = score_group(nodes)
              next if score.negative?

              (best_nodes = nodes) && (best_score = score) if score > best_score
            end

            best_nodes
          end

          def score_group(nodes)
            avg_w = avg_words(nodes)
            return -1 if avg_w < 5

            score = nodes.size + (avg_w / 5.0)
            score += 20 if nodes_heading?(nodes)
            score += 20 if nodes_time?(nodes)
            score += 40 if nodes_date?(nodes)
            score
          end

          def nodes_heading?(nodes)
            nodes.any? do |n|
              n.at_css(HtmlExtractor::HEADING_TAGS.join(',')) ||
                n.at_css('.font-bold, .font-semibold')
            end
          end

          def nodes_time?(nodes)
            nodes.any? { |n| n.at_css('time, [datetime]') }
          end

          def nodes_date?(nodes)
            nodes.any? { |n| date?(n) }
          end

          def avg_words(nodes)
            nodes.sum { |n| text_words(n) } / nodes.size.to_f
          end

          def text_words(node)
            @text_words[node] ||= HtmlExtractor.extract_visible_text(node).to_s.scan(/\p{Alnum}+/).size
          end

          def date?(node)
            @has_date[node] ||= begin
              text = HtmlExtractor.extract_visible_text(node).to_s
              text.match?(%r{\b\d{4}[-/]\d{2}[-/]\d{2}\b}) ||
                text.match?(/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/i)
            end
          end
          # rubocop:enable Metrics/ClassLength
        end
      end
    end
  end
end
