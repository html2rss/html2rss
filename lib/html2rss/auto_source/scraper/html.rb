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
        DEFAULT_USE_TOP_SELECTORS = 5

        def self.options_key = :html

        def self.articles?(parsed_body)
          new(parsed_body, url: '').any?
        end

        ##
        # Simplify an XPath selector by removing the index notation.
        def self.simplify_xpath(xpath)
          xpath.gsub(/\[\d+\]/, '')
        end

        def initialize(parsed_body, url:, **opts)
          @parsed_body = parsed_body
          @url = url
          @opts = opts
        end

        attr_reader :parsed_body

        ##
        # @yieldparam [Hash] The scraped article hash
        # @return [Enumerator] Enumerator for the scraped articles
        def each
          return enum_for(:each) unless block_given?

          filtered_selectors.each do |selector|
            parsed_body.xpath(selector).each do |selected_tag|
              next if selected_tag.path.match?(Html::TAGS_TO_IGNORE)

              article_tag = HtmlNavigator.parent_until_condition(selected_tag, method(:article_condition))

              if article_tag && (article_hash = HtmlExtractor.new(article_tag, base_url: @url).call)
                yield article_hash
              end
            end
          end
        end

        def article_condition(node)
          # Ignore tags that are below a tag which is in TAGS_TO_IGNORE.
          return false if node.path.match?(TAGS_TO_IGNORE)

          return true if %w[body html].include?(node.name)

          count_of_anchors_below = node.name == 'a' ? 1 : node.css('a').size

          return true if node.parent.css('a').size > count_of_anchors_below

          false
        end

        private

        ##
        # Find all the anchors in root.
        # @return [Set<String>] The set of XPath selectors which exist at least min_frequency times
        def selectors
          @selectors ||= Hash.new(0).tap do |selectors|
            @parsed_body.at_css('body').traverse do |node|
              next if !node.element? || node.name != 'a' || String(node['href']).empty?

              path = self.class.simplify_xpath(node.path)
              next if path.match?(TAGS_TO_IGNORE)

              selectors[path] += 1
            end
          end
        end

        ##
        # Filter the frequent selectors by the minimum_selector_frequency and use_top_selectors.
        # @return [Array<String>] The filtered selectors
        def filtered_selectors
          selectors.keys.sort_by { |key| selectors[key] }
                   .last(use_top_selectors)
                   .filter_map do |key|
            selectors[key] >= minimum_selector_frequency ? key : nil
          end
        end

        def minimum_selector_frequency = @opts[:minimum_selector_frequency] || DEFAULT_MINIMUM_SELECTOR_FREQUENCY
        def use_top_selectors = @opts[:use_top_selectors] || DEFAULT_USE_TOP_SELECTORS
      end
    end
  end
end
