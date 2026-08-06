# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      module Discovery
        class ClassClustering
          ##
          # Scores class groups using heading, time, date, and word-count signals.
          class GroupScorer
            def initialize
              @text_words = {}.compare_by_identity
              @has_date = {}.compare_by_identity
            end

            # @param groups [Hash{String => Array<Nokogiri::XML::Node>}] candidate class groups
            # @return [Array<Nokogiri::XML::Node>] nodes from the highest-scoring group
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

            # @param nodes [Array<Nokogiri::XML::Node>]
            # @return [Float] average visible word count across nodes
            def avg_words(nodes)
              nodes.sum { |n| text_words(n) } / nodes.size.to_f
            end

            private

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
                n.at_css(Html2rss::Html::Navigator::HEADING_TAGS.join(',')) ||
                  n.at_css('.font-bold, .font-semibold')
              end
            end

            def nodes_time?(nodes)
              nodes.any? { |n| n.at_css('time, [datetime]') }
            end

            def nodes_date?(nodes)
              nodes.any? { |n| date?(n) }
            end

            def text_words(node)
              @text_words[node] ||= Html2rss::Html::Navigator.extract_visible_text(node).to_s.scan(/\p{Alnum}+/).size
            end

            def date?(node)
              @has_date[node] ||= begin
                text = Html2rss::Html::Navigator.extract_visible_text(node).to_s
                text.match?(%r{\b\d{4}[-/]\d{2}[-/]\d{2}\b}) ||
                  text.match?(/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/i)
              end
            end
          end
        end
      end
    end
  end
end
