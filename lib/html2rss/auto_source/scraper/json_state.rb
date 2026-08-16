# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes JSON state blobs embedded in script tags such as Next.js, Nuxt,
      # or custom window globals. The scraper searches `<script type="application/json">`
      # tags and well-known JavaScript globals for arrays of article-like hashes
      # and normalises them to a structure compatible with Html2rss::Html::ArticleExtractor.
      class JsonState
        include Enumerable

        # @return [Symbol] scraper config key
        def self.options_key = :json_state

        class << self
          # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
          def articles?(parsed_body)
            return false unless parsed_body

            DocumentScanner.json_documents(parsed_body).any? { CandidateDetector.candidate_array?(_1) }
          end

          # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
          # @return [Array<Hash, Array>] parsed JSON documents discovered in the response body
          def json_documents(parsed_body)
            DocumentScanner.json_documents(parsed_body)
          end

          # Walks a JSON document tree and yields normalized article hashes.
          # Shared with {XhrArticles} so XHR-captured JSON reuses one discovery algorithm.
          #
          # @param document [Hash, Array, Object] parsed JSON document node
          # @param base_url [String, Html2rss::Url] base URL for relative link resolution
          # @yield [Hash{Symbol => Object}, nil] normalized article hash
          # @return [void]
          def discover_articles(document, base_url:, &block)
            case document
            when Array then handle_array(document, base_url:, &block)
            when Hash then document.each_value { discover_articles(_1, base_url:, &block) if traversable?(_1) }
            end
          end

          private

          def handle_array(array, base_url:, &block)
            if CandidateDetector.array_of_articles?(array)
              array.each do |entry|
                yield(ArticleNormalizer.normalise(entry, base_url:))
              end
            else
              array.each { discover_articles(_1, base_url:, &block) if traversable?(_1) }
            end
          end

          def traversable?(value)
            value.is_a?(Array) || value.is_a?(Hash)
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
        # @param url [String, Html2rss::Url] page URL used to resolve relative links
        # @param _opts [Hash] scraper-specific options
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        def initialize(parsed_body, url:, **_opts)
          @parsed_body = parsed_body
          @url = url
        end

        attr_reader :parsed_body

        # @return [Boolean] true when the page contains article-like arrays in JSON state
        def extractable?
          json_documents.any? { CandidateDetector.candidate_array?(_1) }
        end

        # @yield [Hash{Symbol => Object}] normalized article hash
        # @return [Enumerator, void] article enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?

          json_documents.each do |document|
            self.class.discover_articles(document, base_url: url) do |article|
              yield article if article
            end
          end
        end

        private

        attr_reader :url

        def json_documents
          self.class.json_documents(parsed_body)
        end
      end
    end
  end
end
