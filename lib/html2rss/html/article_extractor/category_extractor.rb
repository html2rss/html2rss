# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      ##
      # CategoryExtractor is responsible for extracting categories from HTML elements
      # by looking for CSS class names containing common category-related terms.
      class CategoryExtractor
        # Shared category vocabulary (owned by {ArticleRules::Category}).
        CATEGORY_TERMS = ArticleRules::Category::CATEGORY_TERMS

        # CSS selectors to find elements with category-related class names or data attributes
        CATEGORY_SELECTORS = CATEGORY_TERMS.flat_map do |term|
          ["[class*=\"#{term}\"]", "[data-#{term}]", "[#{term}]"]
        end.freeze

        # Nested blocks that mean a "category" node is actually a content container.
        CONTAINER_CHILD_SELECTOR = 'p, article, section, h1, h2, h3, h4, h5, h6'

        ##
        # Extracts categories from the given article tag by looking for elements
        # with class names containing common category-related terms.
        #
        # @param article_tag [Nokogiri::XML::Element] The article element to extract categories from
        # @param title [String, nil] article title used to reject title-echo values
        # @return [Array<String>] Array of category strings, empty if none found
        def self.call(article_tag, title: nil)
          return [] unless article_tag

          extract_all_categories(article_tag, title:)
            .map(&:strip)
            .reject(&:empty?)
        end

        ##
        # Optimized single DOM traversal that extracts all category types.
        #
        # @param article_tag [Nokogiri::XML::Element] The article element
        # @param title [String, nil]
        # @return [Set<String>] Set of category strings
        def self.extract_all_categories(article_tag, title: nil)
          Set.new.tap do |categories|
            extract_element_data_categories!(categories, article_tag, title:)
            article_tag.css(CATEGORY_SELECTORS.join(',')).each do |element|
              next if element == article_tag

              if ArticleRules::Category.class_match?(element['class'])
                extract_text_categories!(categories, element, title:)
              end
              extract_element_data_categories!(categories, element, title:)
            end
          end
        end

        ##
        # Extracts categories from data attributes of a single element.
        #
        # @param categories [Set<String>] Accumulator set
        # @param element [Nokogiri::XML::Element] metadata element that may contain category links
        # @param title [String, nil]
        # @return [void]
        def self.extract_element_data_categories!(categories, element, title: nil)
          element.attributes.each_value do |attr|
            next unless ArticleRules::Category.attr_name_match?(attr.name)

            ArticleRules::Category.add_text!(categories, attr.value, title:)
          end
        end

        ##
        # Extracts text-based categories from elements, splitting content into discrete values.
        #
        # @param categories [Set<String>] Accumulator set
        # @param element [Nokogiri::XML::Element] metadata element whose text may contain delimiters
        # @param title [String, nil]
        # @return [void]
        def self.extract_text_categories!(categories, element, title: nil)
          return if category_container?(element)

          anchors = element.name == 'a' ? [element] : element.css('a').to_a
          if anchors.any?
            anchors.each { |node| add_text_to_categories!(categories, node, title:) }
            return
          end

          ArticleRules::Category.add_split_text!(
            categories, Navigator.extract_visible_text(element), title:
          )
        end

        ##
        # Adds the visible text of the given element to the categories set.
        #
        # @param categories [Set<String>] Accumulator set
        # @param element [Nokogiri::XML::Element] The element to extract text from
        # @param title [String, nil]
        # @return [void]
        def self.add_text_to_categories!(categories, element, title: nil)
          ArticleRules::Category.add_text!(categories, Navigator.extract_visible_text(element), title:)
        end

        def self.category_container?(element)
          element.at_css(CONTAINER_CHILD_SELECTOR)
        end

        private_class_method :add_text_to_categories!, :category_container?
      end
    end
  end
end
