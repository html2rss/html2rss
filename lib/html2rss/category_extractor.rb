# frozen_string_literal: true

module Html2rss
  ##
  # CategoryExtractor is responsible for extracting categories from HTML elements
  # by looking for CSS class names containing common category-related terms.
  class CategoryExtractor
    # Common category-related terms to look for in class names
    CATEGORY_TERMS = %w[category tag topic section label theme subject].freeze

    # CSS selectors to find elements with category-related class names or data attributes
    CATEGORY_SELECTORS = CATEGORY_TERMS.flat_map do |term|
      ["[class*=\"#{term}\"]", "[data-#{term}]", "[#{term}]"]
    end.freeze

    # Regex pattern for matching category-related attribute names
    CATEGORY_ATTR_PATTERN = /#{CATEGORY_TERMS.join('|')}/i

    ##
    # Extracts categories from the given article tag by looking for elements
    # with class names containing common category-related terms.
    #
    # @param article_tag [Nokogiri::XML::Element] The article element to extract categories from
    # @return [Array<String>] Array of category strings, empty if none found
    def self.call(article_tag)
      return [] unless article_tag

      # Single optimized traversal that extracts all category types
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
          # Extract text categories from elements with category-related class names
          extract_text_categories!(categories, element) if element['class']&.match?(CATEGORY_ATTR_PATTERN)

          # Extract data categories from all elements
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
        next unless attr.name.match?(CATEGORY_ATTR_PATTERN)

        value = attr.value&.strip
        categories.add(value) if value && !value.empty?
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
        extract_split_text_categories!(categories, element)
      end
    end

    ##
    # Adds the visible text of the given element to the categories set.
    #
    # @param categories [Set<String>] Accumulator set
    # @param element [Nokogiri::XML::Element] The element to extract text from
    # @return [void]
    def self.add_text_to_categories!(categories, element)
      text = HtmlExtractor.extract_visible_text(element)
      categories.add(text) if text && !text.empty?
    end

    ##
    # Extracts categories from the element's text by splitting on newlines.
    #
    # @param categories [Set<String>] Accumulator set
    # @param element [Nokogiri::XML::Element] The element to extract text from
    # @return [void]
    def self.extract_split_text_categories!(categories, element)
      text = HtmlExtractor.extract_visible_text(element)
      return unless text

      text.split(/\n+/).each do |line|
        line = line.strip
        categories.add(line) unless line.empty?
      end
    end

    private_class_method :add_text_to_categories!, :extract_split_text_categories!
  end
end
