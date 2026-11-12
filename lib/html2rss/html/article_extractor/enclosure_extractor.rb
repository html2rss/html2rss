# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      ##
      # Adapts Nokogiri elements to {ArticleRules::Enclosure}, which owns which elements become enclosures.
      class EnclosureExtractor
        # CSS union of the element names {ArticleRules::Enclosure} may turn into an enclosure.
        SELECTOR = ArticleRules::Enclosure::ELEMENT_NAMES.join(',').freeze
        # CSS union of the players a +source+ element must sit inside.
        PLAYERS = ArticleRules::Enclosure::MEDIA_ELEMENTS.join(',').freeze

        # @param article_tag [Nokogiri::XML::Element] article container node
        # @param base_url [String, Html2rss::Url] base URL for relative enclosure links
        # @return [Array<Hash{Symbol => Object}>] normalized enclosure hashes in document order
        def self.call(article_tag, base_url)
          article_tag.css(SELECTOR).filter_map do |element|
            attrs = { src: element['src'], href: element['href'], type: element['type'] }
            ArticleRules::Enclosure.from_element(element.name, base_url, **attrs) { element.ancestors(PLAYERS).any? }
          end
        end
      end
    end
  end
end
