# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
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
        article_tag.css(SELECTOR).filter_map do |element|
          extract_from_element(element, base_url)
        end
      end

      def self.extract_from_element(element, base_url)
        case element.name
        when 'img'
          extract_image(element, base_url)
        when 'video', 'audio', 'source'
          extract_media(element, base_url)
        when 'iframe'
          extract_iframe(element, base_url)
        when 'a'
          extract_a(element, base_url)
        end
      end

      def self.extract_image(img, base_url)
        src = img['src'].to_s
        return if src.empty?

        abs_url = Url.from_relative(src, base_url)
        {
          url: abs_url,
          type: RssBuilder::Enclosure.guess_content_type_from_url(abs_url, default: 'image/jpeg')
        }
      end

      def self.extract_media(element, base_url)
        src = element['src'].to_s
        return if src.empty?

        {
          url: Url.from_relative(src, base_url),
          type: element['type']
        }
      end

      def self.extract_iframe(iframe, base_url)
        src = iframe['src'].to_s
        return if src.empty?

        abs_url = Url.from_relative(src, base_url)
        {
          url: abs_url,
          type: RssBuilder::Enclosure.guess_content_type_from_url(abs_url, default: 'text/html')
        }
      end

      def self.extract_a(link, base_url)
        href = link['href'].to_s
        return if href.empty?

        abs_url = Url.from_relative(href, base_url)

        if href.end_with?('.pdf')
          { url: abs_url, type: RssBuilder::Enclosure.guess_content_type_from_url(abs_url) }
        else
          { url: abs_url, type: 'application/zip' }
        end
      end

      private_class_method :extract_from_element, :extract_image, :extract_media, :extract_iframe, :extract_a
    end
  end
end
