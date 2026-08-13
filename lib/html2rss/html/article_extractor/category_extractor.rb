# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      ##
      # CategoryExtractor is responsible for extracting categories from HTML elements
      # by looking for CSS class names containing common category-related terms.
      class CategoryExtractor
        CATEGORY_TERMS = ArticleRules::Category::CATEGORY_TERMS
        CATEGORY_ATTR_PATTERN = ArticleRules::Category::CATEGORY_ATTR_PATTERN

        # CSS selectors to find elements with category-related class names or data attributes
        CATEGORY_SELECTORS = CATEGORY_TERMS.flat_map do |term|
          ["[class*=\"#{term}\"]", "[data-#{term}]", "[#{term}]"]
        end.freeze

        ##
        # Extracts categories from the given article tag by looking for elements
        # with class names containing common category-related terms.
        #
        # @param article_tag [Nokogiri::XML::Element] The article element to extract categories from
        # @return [Array<String>] Array of category strings, empty if none found
        def self.call(article_tag)
          return [] unless article_tag

          extract_all_categories(article_tag)
            .map(&:strip)
            .reject(&:empty?)
        end

        ##
        # Optimized single DOM traversal that extracts all category types.
        #
        # @param article_tag [Nokogiri::XML::Element] The article element
        # @return [Set<String>] Set of category strings
        def self.extract_all_categories(article_tag)
          Set.new.tap do |categories|
            article_tag.css(CATEGORY_SELECTORS.join(',')).each do |element|
              extract_text_categories!(categories, element) if ArticleRules::Category.class_match?(element['class'])
              extract_element_data_categories!(categories, element)
            end
          end
        end

        ##
        # Extracts categories from data attributes of a single element.
        #
        # @param categories [Set<String>] Accumulator set
        # @param element [Nokogiri::XML::Element] metadata element that may contain category links
        # @return [void]
        def self.extract_element_data_categories!(categories, element)
          element.attributes.each_value do |attr|
            next unless ArticleRules::Category.attr_name_match?(attr.name)

            ArticleRules::Category.add_text!(categories, attr.value)
          end
        end

        ##
        # Extracts text-based categories from elements, splitting content into discrete values.
        #
        # @param categories [Set<String>] Accumulator set
        # @param element [Nokogiri::XML::Element] metadata element whose text may contain delimiters
        # @return [void]
        def self.extract_text_categories!(categories, element)
          if element.name == 'a'
            add_text_to_categories!(categories, element)
            return
          end

          anchors = element.css('a')

          if anchors.any?
            anchors.each { |node| add_text_to_categories!(categories, node) }
          else
            ArticleRules::Category.add_split_text!(categories, element.text)
          end
        end

        ##
        # Adds the visible text of the given element to the categories set.
        #
        # @param categories [Set<String>] Accumulator set
        # @param element [Nokogiri::XML::Element] The element to extract text from
        # @return [void]
        def self.add_text_to_categories!(categories, element)
          ArticleRules::Category.add_text!(categories, Navigator.extract_visible_text(element))
        end

        private_class_method :add_text_to_categories!
      end
    end
  end
end
