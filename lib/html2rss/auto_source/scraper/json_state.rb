# frozen_string_literal: true

require 'json'

module Html2rss
  class AutoSource
    module Scraper
      #
      # Scrapes JSON state blobs embedded in script tags such as Next.js, Nuxt,
      # or custom window globals. The scraper searches `<script type="application/json">`
      # tags and well-known JavaScript globals for arrays of article-like hashes
      # and normalises them to a structure compatible with HtmlExtractor.
      class JsonState
        include Enumerable

        JSON_SCRIPT_SELECTOR = 'script[type="application/json"]'
        GLOBAL_ASSIGNMENT_PATTERNS = [
          /(?:window|self|globalThis)\.__NEXT_DATA__\s*=\s*/m,
          /(?:window|self|globalThis)\.__NUXT__\s*=\s*/m,
          /(?:window|self|globalThis)\.STATE\s*=\s*/m
        ].freeze

        TITLE_KEYS = %w[title headline name text].freeze
        URL_KEYS = %w[url link href permalink slug path canonicalUrl shortUrl].freeze
        DESCRIPTION_KEYS = %w[description summary excerpt dek subheading].freeze
        IMAGE_KEYS = %w[image imageUrl thumbnailUrl thumbnail src featuredImage coverImage heroImage].freeze
        PUBLISHED_AT_KEYS = %w[published_at publishedAt datePublished date publicationDate pubDate updatedAt updated_at
                               createdAt created_at].freeze
        CATEGORY_KEYS = %w[categories tags section sections topic topics channel].freeze
        ID_KEYS = %w[id guid uuid slug key].freeze

        # Scans DOM nodes for JSON payloads containing article data.
        module DocumentScanner
          module_function

          def json_documents(parsed_body)
            script_documents(parsed_body) + assignment_documents(parsed_body)
          end

          def script_documents(parsed_body)
            parsed_body.css(JSON_SCRIPT_SELECTOR).filter_map { parse_json(_1.text) }
          end

          def assignment_documents(parsed_body)
            parsed_body.css('script').filter_map { parse_assignment(_1.text) }
          end

          def parse_assignment(text)
            payload = assignment_payload(text)
            parse_json(payload) if payload
          end

          def assignment_payload(text)
            trimmed = text.to_s.strip
            return if trimmed.empty?

            GLOBAL_ASSIGNMENT_PATTERNS.each do |pattern|
              next unless trimmed.match?(pattern)

              payload = trimmed.sub(pattern, '')
              return extract_assignment_payload(payload)
            end

            nil
          end

          def extract_assignment_payload(text)
            extract_json_block(text) || text
          end

          def extract_json_block(text)
            start_index = text.index(/[\[{]/)
            return unless start_index

            stop_index = scan_for_json_end(text, start_index)
            text[start_index..stop_index] if stop_index
          end

          # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          def scan_for_json_end(text, start_index)
            stack = []
            in_string = false
            escape = false

            text.each_char.with_index do |char, index|
              next if index < start_index

              if in_string
                if escape
                  escape = false
                elsif char == '\\'
                  escape = true
                elsif char == '"'
                  in_string = false
                end
                next
              end

              case char
              when '"'
                in_string = true
              when '{'
                stack << '}'
              when '['
                stack << ']'
              when '}', ']'
                expected = stack.pop
                return index if expected == char && stack.empty?
              end
            end

            nil
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

          def parse_json(payload)
            return unless payload

            JSON.parse(payload, symbolize_names: true)
          rescue JSON::ParserError => error
            Log.debug('JsonState: Failed to parse JSON payload', error: error.message)
            nil
          end
        end
        private_constant :DocumentScanner

        # Retrieves values from heterogeneous objects by probing multiple keys.
        module ValueFinder
          module_function

          def fetch(object, keys)
            case object
            when Hash then fetch_from_hash(object, keys)
            when Array then fetch_from_array(object, keys)
            end
          end

          def fetch_from_hash(hash, keys)
            keys.each do |key|
              string_key = key.to_s
              return hash[string_key] if hash.key?(string_key)

              symbol_key = string_key.to_sym
              return hash[symbol_key] if hash.key?(symbol_key)
            end

            fetch_nested(hash[:attributes] || hash['attributes'], keys) ||
              fetch_nested(hash[:data] || hash['data'], keys)
          end

          def fetch_from_array(array, keys)
            array.each do |entry|
              result = fetch(entry, keys)
              return result if result
            end

            nil
          end

          def fetch_nested(value, keys)
            fetch(value, keys) if value
          end
        end
        private_constant :ValueFinder

        # Identifies arrays that look like collections of article hashes.
        module CandidateDetector
          module_function

          def candidate_array?(document)
            case document
            when Array then array_of_articles?(document)
            when Hash then document.each_value.any? { candidate_array?(_1) }
            else false
            end
          end

          def array_of_articles?(array)
            array.any? do |element|
              next unless element.is_a?(Hash)

              title_from(element) && url_from(element)
            end
          end

          def title_from(object)
            ValueFinder.fetch(object, TITLE_KEYS)
          end

          def url_from(object)
            ValueFinder.fetch(object, URL_KEYS)
          end
        end
        private_constant :CandidateDetector

        # Shapes raw entries into the structure required downstream.
        module ArticleNormalizer
          module_function

          # rubocop:disable Metrics/MethodLength
          def normalise(entry, base_url:)
            return unless entry.is_a?(Hash)

            title = string(ValueFinder.fetch(entry, TITLE_KEYS))
            description = string(ValueFinder.fetch(entry, DESCRIPTION_KEYS))
            article_url = resolve_link(entry, keys: URL_KEYS, base_url:,
                                              log_key: 'JsonState: invalid URL encountered')
            return unless article_url
            return if title.nil? && description.nil?

            {
              title:,
              description:,
              url: article_url,
              image: resolve_link(entry, keys: IMAGE_KEYS, base_url:,
                                         log_key: 'JsonState: invalid image URL encountered'),
              published_at: string(ValueFinder.fetch(entry, PUBLISHED_AT_KEYS)),
              categories: categories(entry),
              id: identifier(entry, article_url)
            }.compact
          end
          # rubocop:enable Metrics/MethodLength

          def string(value)
            trimmed = value.to_s.strip
            trimmed unless trimmed.empty?
          end

          def resolve_link(entry, keys:, base_url:, log_key:)
            value = ValueFinder.fetch(entry, keys)
            value = ValueFinder.fetch(value, keys) if value.is_a?(Hash)
            string = string(value)
            return unless string

            Url.from_relative(string, base_url)
          rescue ArgumentError
            Log.debug(log_key, url: string)
            nil
          end

          # rubocop:disable Metrics/MethodLength
          def categories(entry)
            raw = ValueFinder.fetch(entry, CATEGORY_KEYS)
            names = case raw
                    when Array then raw
                    when Hash then raw.values
                    when String then [raw]
                    else []
                    end

            result = names.flat_map do |value|
              case value
              when Hash
                string(ValueFinder.fetch(value, %w[name title label]))
              else
                string(value)
              end
            end.compact

            result.uniq!
            result unless result.empty?
          end
          # rubocop:enable Metrics/MethodLength

          def identifier(entry, article_url)
            value = ValueFinder.fetch(entry, ID_KEYS)
            value = ValueFinder.fetch(value, ID_KEYS) if value.is_a?(Hash)
            string(value) || article_url.to_s
          end
        end
        private_constant :ArticleNormalizer

        def self.options_key = :json_state

        class << self
          def articles?(parsed_body)
            return false unless parsed_body

            DocumentScanner.json_documents(parsed_body).any? { CandidateDetector.candidate_array?(_1) }
          end

          def json_documents(parsed_body)
            DocumentScanner.json_documents(parsed_body)
          end
        end

        def initialize(parsed_body, url:, **_opts)
          @parsed_body = parsed_body
          @url = url
        end

        attr_reader :parsed_body

        def each
          return enum_for(:each) unless block_given?

          DocumentScanner.json_documents(parsed_body).each do |document|
            discover_articles(document) do |article|
              yield article if article
            end
          end
        end

        private

        attr_reader :url

        def discover_articles(document, &block)
          case document
          when Array then handle_array(document, &block)
          when Hash then document.each_value { discover_articles(_1, &block) if traversable?(_1) }
          end
        end

        def handle_array(array, &block)
          if CandidateDetector.array_of_articles?(array)
            array.each do |entry|
              yield(ArticleNormalizer.normalise(entry, base_url: url))
            end
          else
            array.each { discover_articles(_1, &block) if traversable?(_1) }
          end
        end

        def traversable?(value)
          value.is_a?(Array) || value.is_a?(Hash)
        end
      end
    end
  end
end
