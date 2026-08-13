# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      ##
      # Extracts enclosures from HTML tags using various strategies.
      class EnclosureExtractor
        # CSS union query covering images, media, PDFs, iframes, and archives.
        SELECTOR = [
          'img[src]:not([src^="data"])',
          'video source[src]',
          'audio source[src]',
          'audio[src]',
          'a[href$=".pdf"]',
          'iframe[src]',
          'a[href$=".zip"]',
          'a[href$=".tar.gz"]',
          'a[href$=".tgz"]'
        ].join(',').freeze

        # @param article_tag [Nokogiri::XML::Element] article container node
        # @param base_url [String, Html2rss::Url] base URL for relative enclosure links
        # @return [Array<Hash{Symbol => Object}>] normalized enclosure hashes
        def self.call(article_tag, base_url)
          return [] unless article_tag

          article_tag.css(SELECTOR).filter_map do |element|
            extract_from_element(element, base_url)
          end
        end

        def self.extract_from_element(element, base_url)
          case element.name
          when 'img'
            ArticleRules::Enclosure.from_image(element['src'], base_url)
          when 'video', 'audio', 'source'
            ArticleRules::Enclosure.from_media(element['src'], element['type'], base_url)
          when 'iframe'
            ArticleRules::Enclosure.from_iframe(element['src'], base_url)
          when 'a'
            ArticleRules::Enclosure.from_anchor(element['href'], base_url)
          end
        end

        private_class_method :extract_from_element
      end
    end
  end
end
