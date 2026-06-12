# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    ##
    # Builds repeated-list article container candidates from generic HTML.
    class ListCandidates
      ##
      # Simplify an XPath selector by removing index notation.
      #
      # @param xpath [String] original XPath
      # @return [String] XPath without positional indexes
      def self.simplify_xpath(xpath)
        xpath.gsub(/\[\d+\]/, '')
      end

      # @param parsed_body [Nokogiri::HTML::Document] parsed document
      # @param minimum_selector_frequency [Integer] minimum repeated anchor path count
      # @param use_top_selectors [Integer] number of frequent anchor paths to inspect
      def initialize(parsed_body, minimum_selector_frequency:, use_top_selectors:)
        @parsed_body = parsed_body
        @minimum_selector_frequency = minimum_selector_frequency
        @use_top_selectors = use_top_selectors
      end

      ##
      # @param anchor_filter [#call] predicate for scraper-specific anchor eligibility
      # @param boundary_condition [#call] predicate for article container boundary
      # @yieldparam article_tag [Nokogiri::XML::Node] candidate article container
      # @yieldparam selected_anchor [Nokogiri::XML::Node] anchor that made the container eligible
      # @return [Enumerator]
      def each_article_tag(anchor_filter:, boundary_condition:)
        return enum_for(:each_article_tag, anchor_filter:, boundary_condition:) unless block_given?

        article_tags(anchor_filter:, boundary_condition:).each { yield _1[:article_tag], _1[:selected_anchor] }
      end

      private

      attr_reader :parsed_body, :minimum_selector_frequency, :use_top_selectors

      def article_tags(anchor_filter:, boundary_condition:)
        selectors(anchor_filter:).flat_map do |selector|
          article_tags_for_selector(selector, boundary_condition)
        end
      end

      def article_tags_for_selector(selector, boundary_condition)
        parsed_body.xpath(selector).filter_map do |selected_tag|
          next if HtmlExtractor.ignored_container_path?(selected_tag)

          article_tag = HtmlNavigator.parent_until_condition(selected_tag, boundary_condition)
          next unless article_tag

          { article_tag:, selected_anchor: selected_tag }
        end
      end

      def selectors(anchor_filter:)
        anchor_counts(anchor_filter:)
          .select { |_selector, count| count >= minimum_selector_frequency }
          .max_by(use_top_selectors, &:last)
          .map(&:first)
      end

      def anchor_counts(anchor_filter:)
        Hash.new(0).tap do |counts|
          each_anchor(anchor_filter:) do |node|
            path = self.class.simplify_xpath(node.path)
            counts[path] += 1 unless HtmlExtractor.ignored_container_path?(path)
          end
        end
      end

      def each_anchor(anchor_filter:)
        return enum_for(:each_anchor, anchor_filter:) unless block_given?

        traversal_root&.css(HtmlExtractor::MAIN_ANCHOR_SELECTOR)&.each do |node|
          yield node if anchor_filter.call(node)
        end
      end

      def traversal_root
        parsed_body.at_css('body, html') || parsed_body.root
      end
    end
  end
end
