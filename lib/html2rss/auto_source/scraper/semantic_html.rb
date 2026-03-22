# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes semantic containers by selecting a single content-like anchor
      # within each block before extraction.
      class SemanticHtml
        include Enumerable

        CONTAINER_SELECTORS = [
          'article:not(:has(article))',
          'section:not(:has(section))',
          'li:not(:has(li))',
          'tr:not(:has(tr))',
          'div:not(:has(div))'
        ].freeze
        HEADING_SELECTOR = HtmlExtractor::HEADING_TAGS.join(',').freeze
        UTILITY_PATH_SEGMENTS = %w[
          about account author category comment comments contact feedback help
          login newsletter profile register search settings share signup tag tags
          user users
        ].freeze
        CONTENT_PATH_SEGMENTS = %w[
          article articles news post posts story stories update updates
        ].freeze

        def self.options_key = :semantic_html

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @return [Boolean] true when semantic containers exist in the document
        def self.articles?(parsed_body)
          !!parsed_body&.at_css(CONTAINER_SELECTORS.join(','))
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base url
        # @param extractor [Class] extractor class used for article extraction
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **_opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
        end

        attr_reader :parsed_body

        ##
        # @yieldparam article_hash [Hash] extracted article hash
        # @return [Enumerator]
        def each
          return enum_for(:each) unless block_given?

          candidate_containers.each do |container|
            selected_anchor = primary_anchor_for(container)
            next unless selected_anchor

            article_hash = @extractor.new(container, base_url: @url, selected_anchor:).call
            yield article_hash if article_hash
          end
        end

        private

        def candidate_containers
          seen = {}

          CONTAINER_SELECTORS.flat_map { |selector| parsed_body.css(selector).to_a }.filter_map do |container|
            next if container.path.match?(Html::TAGS_TO_IGNORE)
            next if seen[container.path]

            seen[container.path] = true
            container
          end
        end

        def primary_anchor_for(container)
          representative_anchors(container)
            .filter_map { |anchor| score_anchor(container, anchor) }
            .max_by(&:last)
            &.first
        end

        def representative_anchors(container)
          eligible_anchors(container)
            .group_by { |anchor| normalized_destination(anchor) }
            .values
            .filter_map { |anchors| best_anchor_for_group(container, anchors) }
        end

        def eligible_anchors(container)
          container.css(HtmlExtractor::MAIN_ANCHOR_SELECTOR).select do |anchor|
            next false if anchor.path.match?(Html::TAGS_TO_IGNORE)

            eligible_anchor?(container, anchor)
          end
        end

        def eligible_anchor?(container, anchor)
          return false if utility_anchor?(anchor)
          return false if icon_only_anchor?(anchor)

          heading_anchor?(container, anchor) || content_like_anchor?(anchor)
        end

        def utility_anchor?(anchor)
          utility_destination?(anchor) || utility_text?(anchor_text(anchor))
        end

        def content_like_anchor?(anchor)
          meaningful_text?(anchor_text(anchor)) || content_like_destination?(anchor)
        end

        def best_anchor_for_group(container, anchors)
          anchors.max_by do |anchor|
            score_anchor(container, anchor)&.last.to_i
          end
        end

        def score_anchor(container, anchor)
          return unless eligible_anchor?(container, anchor)

          score = 0
          score += 100 if heading_anchor?(container, anchor)
          score += 20 if heading_text_match?(container, anchor)
          score += 10 if meaningful_text?(anchor_text(anchor))
          score += 10 if content_like_destination?(anchor)

          [anchor, score]
        end

        def heading_anchor?(container, anchor)
          anchor.ancestors.any? { |node| node == heading_for(container) }
        end

        def heading_text_match?(container, anchor)
          heading_text = visible_text(heading_for(container))
          anchor_text = anchor_text(anchor)

          meaningful_text?(heading_text) && heading_text == anchor_text
        end

        def heading_for(container)
          container.at_css(HEADING_SELECTOR)
        end

        def icon_only_anchor?(anchor)
          !meaningful_text?(anchor_text(anchor)) && anchor.at_css('img, svg')
        end

        def utility_destination?(anchor)
          segments = destination_segments(anchor)
          return true if segments.empty?

          segments.any? { |segment| UTILITY_PATH_SEGMENTS.include?(segment) }
        end

        def content_like_destination?(anchor)
          segments = destination_segments(anchor)
          return false if segments.empty?

          segments.any? do |segment|
            CONTENT_PATH_SEGMENTS.include?(segment) || segment.match?(/\A\d[\w-]*\z/)
          end
        end

        def destination_segments(anchor)
          destination = normalized_destination(anchor)
          return [] unless destination

          Html2rss::Url.from_absolute(destination).path_segments
        rescue ArgumentError
          []
        end

        def normalized_destination(anchor)
          href = anchor['href'].to_s.split('#').first.to_s.strip
          return if href.empty?

          Html2rss::Url.from_relative(href, @url).to_s
        rescue ArgumentError
          nil
        end

        def utility_text?(text)
          text.match?(/\A(about|contact|log in|login|sign up|signup|share|comments?)\b/i)
        end

        def meaningful_text?(text)
          text.scan(/\p{Alnum}+/).any?
        end

        def anchor_text(anchor)
          visible_text(anchor)
        end

        def visible_text(node)
          return '' unless node

          HtmlExtractor.extract_visible_text(node).to_s.strip
        end
      end
    end
  end
end
