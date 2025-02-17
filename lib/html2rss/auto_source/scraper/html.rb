# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes articles from HTML pages by
      # finding similar structures around anchor tags in the parsed_body.
      class Html
        include Enumerable

        TAGS_TO_IGNORE = /(nav|footer|header)/i

        DEFAULT_MINIMUM_SELECTOR_FREQUENCY = 2

        def self.options_key = :html

        def self.articles?(parsed_body)
          new(parsed_body, url: '').any?
        end

        def self.parent_until_condition(node, condition)
          return nil if !node || node.document? || node.parent.name == 'html'
          return node if condition.call(node)

          parent_until_condition(node.parent, condition)
        end

        ##
        # Simplify an XPath selector by removing the index notation.
        def self.simplify_xpath(xpath)
          xpath.gsub(/\[\d+\]/, '')
        end

        def initialize(parsed_body, url:, **opts)
          @parsed_body = parsed_body
          @url = url
          @selectors = Hash.new(0)
          @opts = opts
        end

        attr_reader :parsed_body

        ##
        # @yieldparam [Hash] The scraped article hash
        # @return [Enumerator] Enumerator for the scraped articles
        def each
          return enum_for(:each) unless block_given?

          return if frequent_selectors.empty?

          frequent_selectors.each do |selector|
            parsed_body.xpath(selector).each do |selected_tag|
              article_tag = HtmlNavigator.parent_until_condition(selected_tag, method(:article_condition))

              if article_tag && (article_hash = HtmlExtractor.new(article_tag, base_url: @url).call)
                yield article_hash
              end
            end
          end
        end

        ##
        # Find all the anchors in root.
        # @param root [Nokogiri::XML::Node] The root node to search for anchors
        # @return [Set<String>] The set of XPath selectors which exist at least min_frequency times
        def frequent_selectors(root = @parsed_body.at_css('body'))
          @frequent_selectors ||= begin
            root.traverse do |node|
              next if !node.element? || node.name != 'a'

              @selectors[self.class.simplify_xpath(node.path)] += 1
            end

            @selectors.keys
                      .select { |selector| (@selectors[selector]).to_i >= minimum_selector_frequency }
                      .to_set
          end
        end

        def article_condition(node)
          # Ignore tags that are below a tag which is in TAGS_TO_IGNORE.
          return false if node.path.match?(TAGS_TO_IGNORE)

          # Ignore tags that are below a tag which has a class which matches TAGS_TO_IGNORE.
          return false if HtmlNavigator.parent_until_condition(node, proc do |current_node|
            current_node.classes.any? { |klass| klass.match?(TAGS_TO_IGNORE) }
          end)

          return true if %w[body html].include?(node.name)

          return true if node.parent.css('a').size > 1

          false
        end

        private

        def minimum_selector_frequency = @opts[:minimum_selector_frequency] || DEFAULT_MINIMUM_SELECTOR_FREQUENCY
      end
    end
  end
end
