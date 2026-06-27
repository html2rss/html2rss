# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    ##
    # HeadingExtractor identifies and returns the best heading element within a container.
    class HeadingExtractor
      # Heading tags used to prioritize title extraction.
      HEADING_TAGS = HtmlExtractor::HEADING_TAGS

      class << self
        ##
        # @param article_tag [Nokogiri::XML::Element] container node
        # @param fallback_anchorless [Boolean] whether to use fallback search
        # @param selected_anchor [Nokogiri::XML::Node, nil] anchor element
        # @return [Nokogiri::XML::Node, nil] the heading node, if found
        def call(article_tag, fallback_anchorless:, selected_anchor:)
          tags = article_tag.css(HEADING_TAGS.join(','))
          if tags.any?
            select_best_heading(tags)
          elsif fallback_anchorless && selected_anchor.nil?
            fallback_heading(article_tag)
          end
        end

        private

        def select_best_heading(tags)
          min_tag_name = tags.map(&:name).min
          best_tag = nil
          max_size = -1

          tags.each do |tag|
            next if tag.name != min_tag_name

            size = TextExtractor.call(tag)&.size.to_i
            (best_tag = tag) && (max_size = size) if size > max_size
          end

          best_tag
        end

        def fallback_heading(article_tag)
          fallback_tags = article_tag.css('strong, b, [class*="title"], [class*="font-bold"], [class*="font-semibold"]')
          fallback_tags.find { |t| !TextExtractor.call(t).to_s.strip.empty? }
        end
      end
    end
  end
end
