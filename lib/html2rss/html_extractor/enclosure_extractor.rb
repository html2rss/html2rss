# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    ##
    # Extracts enclosures from HTML tags using various strategies.
    class EnclosureExtractor
      def self.call(article_tag, base_url)
        [
          Extractors::Media,
          Extractors::Pdf,
          Extractors::Iframe,
          Extractors::Archive
        ].flat_map { |strategy| strategy.call(article_tag, base_url:) }
      end
    end

    module Extractors
      # Extracts image enclosures from HTML tags.
      # Uses the ImageExtractor to find the image source and returns it in a format suitable for RSS.
      class Image
        def self.call(article_tag, base_url:)
          if (img_src = ImageExtractor.call(article_tag, base_url:))
            {
              url: img_src,
              type: RssBuilder::Enclosure.guess_content_type_from_url(img_src, default: 'image/jpeg')
            }
          else
            []
          end
        end
      end

      # Extracts media enclosures (video/audio) from HTML tags.
      class Media
        def self.call(tag, base_url:)
          tag.css('video source[src], audio source[src], audio[src]').filter_map do |element|
            src = element['src'].to_s
            next if src.empty?

            {
              url: Utils.build_absolute_url_from_relative(src, base_url),
              type: element['type']
            }
          end
        end
      end

      # Extracts PDF enclosures from HTML tags.
      class Pdf
        def self.call(tag, base_url:)
          tag.css('a[href$=".pdf"]').map do |a|
            href = a['href'].to_s
            next if href.empty?

            abs_url = Utils.build_absolute_url_from_relative(href, base_url)
            {
              url: abs_url,
              type: RssBuilder::Enclosure.guess_content_type_from_url(abs_url)
            }
          end
        end
      end

      # Extracts iframe enclosures from HTML tags.
      class Iframe
        def self.call(tag, base_url:)
          tag.css('iframe[src]').map do |iframe|
            src = iframe['src']
            abs_url = Utils.build_absolute_url_from_relative(src, base_url)
            {
              url: abs_url,
              type: RssBuilder::Enclosure.guess_content_type_from_url(abs_url,
                                                                      default: 'text/html')
            }
          end
        end
      end

      # Extracts archive enclosures (zip, tar.gz, tgz) from HTML tags.
      class Archive
        def self.call(tag, base_url:)
          tag.css('a[href$=".zip"], a[href$=".tar.gz"], a[href$=".tgz"]').map do |a|
            href = a['href'].to_s
            next if href.empty?

            abs_url = Utils.build_absolute_url_from_relative(href, base_url)

            {
              url: abs_url,
              type: 'application/zip'
            }
          end
        end
      end
    end
  end
end
