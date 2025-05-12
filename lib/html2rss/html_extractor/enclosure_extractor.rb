# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    # Extracts video / audio content (to be used as enclosure) from an article_tag.
    # Extracts video and audio enclosures from an article tag.
    #
    # @param [Nokogiri::XML::Element] article_tag The HTML element containing the article.
    # @param [String] url The base URL to resolve relative URLs.
    # @return [Array<Hash>] Hash contains the enclosure url and type.
    class EnclosureExtractor
      def self.call(article_tag, url)
        article_tag.css('video source[src], audio[src]').filter_map do |tag|
          src = tag['src'].to_s
          next if src.empty?

          {
            url: Utils.build_absolute_url_from_relative(src, url),
            type: tag['type']
          }.compact
        end
      end
    end
  end
end
