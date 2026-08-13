# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Scores DomClustering-style node groups (heading/time/date/word density).
    # Sole home for cluster-group ranking weights.
    class ClusterScorer
      # Minimum average visible words before a group is eligible.
      MIN_AVG_WORDS = 5
      # Bonus when any node has a heading or bold title class.
      HEADING_BONUS = 20
      # Bonus when any node has a time/datetime marker.
      TIME_BONUS = 20
      # Bonus when any node has date-like visible text.
      DATE_BONUS = 40

      def initialize
        @text_words = {}.compare_by_identity
        @has_date = {}.compare_by_identity
      end

      ##
      # @param groups [Hash{String => Array<SST::Node>}]
      # @return [Array<SST::Node>]
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

      ##
      # @param nodes [Array<SST::Node>]
      # @return [Float]
      def avg_words(nodes)
        nodes.sum { |n| text_words(n) } / nodes.size.to_f
      end

      private

      def score_group(nodes)
        avg_w = avg_words(nodes)
        return -1 if avg_w < MIN_AVG_WORDS

        score = nodes.size + (avg_w / 5.0)
        score += HEADING_BONUS if nodes_heading?(nodes)
        score += TIME_BONUS if nodes_time?(nodes)
        score += DATE_BONUS if nodes_date?(nodes)
        score
      end

      def nodes_heading?(nodes)
        nodes.any? do |n|
          n.find(&:heading?) ||
            n.attrs.class_names.any? { |c| c.match?(/font-bold|font-semibold/) }
        end
      end

      def nodes_time?(nodes)
        nodes.any? { |n| n.find { |d| d.name == :time || d.attrs.datetime } }
      end

      def nodes_date?(nodes)
        nodes.any? { |n| date?(n) }
      end

      def text_words(node)
        @text_words[node] ||= node.word_count
      end

      def date?(node)
        @has_date[node] ||= begin
          text = node.visible_text.to_s
          text.match?(%r{\b\d{4}[-/]\d{2}[-/]\d{2}\b}) ||
            text.match?(/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/i)
        end
      end
    end
  end
end
