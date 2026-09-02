# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      ##
      # HeadingExtractor identifies and returns the best heading element within a container.
      class HeadingExtractor
        # Heading tags used to prioritize title extraction.
        HEADING_TAGS = Navigator::HEADING_TAGS

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
            else
              labeled = heading_from_aria_or_title(article_tag)
              return labeled if labeled

              fallback_heading(article_tag) if fallback_anchorless && selected_anchor.nil?
            end
          end

          private

          def select_best_heading(tags)
            min_tag_name = tags.map { Probe.tag(_1) }.min
            best_tag = nil
            max_size = -1

            tags.each do |tag|
              next if Probe.tag(tag) != min_tag_name

              size = Navigator::TextExtractor.call(tag)&.size.to_i
              (best_tag = tag) && (max_size = size) if size > max_size
            end

            best_tag
          end

          def fallback_heading(article_tag)
            fallback_tags = article_tag.css(
              'strong, b, [class*="title"], [class*="font-bold"], [class*="font-semibold"]'
            )
            fallback_tags.find { |t| !Navigator::TextExtractor.call(t).to_s.strip.empty? }
          end

          def heading_from_aria_or_title(article_tag)
            article_tag.css('[aria-label]').each do |node|
              next if node['aria-label'].to_s.strip.empty?

              return node
            end
            article_tag.css('[title]').each do |node|
              next if node['title'].to_s.strip.empty?

              return node
            end
            nil
          end
        end
      end
    end
  end
end
