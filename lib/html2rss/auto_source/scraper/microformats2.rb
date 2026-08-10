# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes h-entry objects based on Microformats2 specifications.
      #
      # @see https://microformats.org/wiki/h-entry
      class Microformats2
        include Enumerable

        # Selector for Microformats2 h-entry containers.
        ENTRY_SELECTOR = '.h-entry, [class*="h-entry"]'

        # @return [Symbol] scraper config key
        def self.options_key = :microformats2

        class << self
          # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
          # @return [Boolean] whether Microformats2 h-entry elements exist
          def articles?(parsed_body)
            return false unless parsed_body

            !parsed_body.at_css(ENTRY_SELECTOR).nil?
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base page URL
        # @param _opts [Hash] unused scraper-specific options
        # @option _opts [Object] :_reserved reserved for future options
        # @return [void]
        def initialize(parsed_body, url:, **_opts)
          @parsed_body = parsed_body
          @url = Html2rss::Url.from_absolute(url)
        end

        ##
        # Yields normalized article hashes extracted from h-entry elements.
        #
        # @yieldparam article [Hash{Symbol => Object}] normalized article hash
        # @return [Enumerator, void] enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?

          parsed_body.css(ENTRY_SELECTOR).each do |entry|
            article = build_article(entry)
            yield article if article
          end
        end

        private

        attr_reader :parsed_body, :url

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [Hash{Symbol => Object}, nil] article hash or nil
        def build_article(entry)
          title = extract_title(entry)
          article_url = extract_url(entry)
          return unless title || article_url

          assemble_article(entry, title, article_url)
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [String, nil] title text
        def extract_title(entry)
          node = entry.at_css('.p-name')
          text = node&.text&.strip
          text unless text.to_s.empty?
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [Html2rss::Url, nil] resolved article URL
        def extract_url(entry)
          node = entry.at_css('.u-url')
          raw_url = node&.attr('href')&.strip
          resolve_url(raw_url)
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @param title [String, nil] article title
        # @param article_url [Html2rss::Url, nil] resolved article URL
        # @return [Hash{Symbol => Object}] assembled article hash
        def assemble_article(entry, title, article_url)
          { title:, url: article_url || url, description: extract_description(entry),
            image: extract_image(entry), author: extract_author(entry),
            published_at: extract_published_at(entry), categories: extract_categories(entry) }.compact
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [String, nil] description text or html
        def extract_description(entry)
          node = entry.at_css('.e-content, .p-summary')
          content = node&.inner_html&.strip || node&.text&.strip
          content unless content.to_s.empty?
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [String, nil] image URL
        def extract_image(entry)
          node = entry.at_css('.u-featured, .u-photo')
          raw_src = node&.attr('src')&.strip || node&.attr('href')&.strip
          resolve_url(raw_src)&.to_s
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [String, nil] author text
        def extract_author(entry)
          node = entry.at_css('.p-author .p-name, .p-author, .h-card .p-name')
          text = node&.text&.strip
          text unless text.to_s.empty?
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [String, nil] published timestamp
        def extract_published_at(entry)
          node = entry.at_css('.dt-published')
          timestamp = node&.attr('datetime')&.strip || node&.text&.strip
          timestamp unless timestamp.to_s.empty?
        end

        # @param entry [Nokogiri::XML::Element] entry DOM node
        # @return [Array<String>, nil] categories array
        def extract_categories(entry)
          categories = entry.css('.p-category').map { _1.text.strip }.reject(&:empty?)
          categories unless categories.empty?
        end

        # @param raw_url [String, nil] raw URL string
        # @return [Html2rss::Url, nil] resolved absolute URL or nil
        def resolve_url(raw_url)
          return if raw_url.to_s.empty?

          Html2rss::Url.from_relative(raw_url, url)
        rescue Html2rss::Url::InvalidUrlError
          nil
        end
      end
    end
  end
end
