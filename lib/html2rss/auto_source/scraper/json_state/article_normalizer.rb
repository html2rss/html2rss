# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Shapes raw entries into the structure required downstream.
        module ArticleNormalizer # rubocop:disable Metrics/ModuleLength -- field keys + URL/scalar unwrap stay co-located
          # Preferred keys when extracting title-like values from state payloads.
          TITLE_KEYS = %i[title headline name text].freeze
          # Preferred keys when extracting URL-like values from state payloads.
          URL_KEYS = %i[url link href permalink slug path canonicalUrl shortUrl alias self].freeze
          # Preferred keys when extracting description-like values from state payloads.
          DESCRIPTION_KEYS = %i[description summary excerpt dek subheading abstract].freeze
          # Preferred keys when extracting image-like values from state payloads.
          IMAGE_KEYS = %i[image imageUrl thumbnailUrl thumbnail src featuredImage coverImage heroImage icon].freeze
          # Preferred keys when extracting publication timestamps from state payloads.
          PUBLISHED_AT_KEYS = %i[published_at publishedAt datePublished date publicationDate pubDate updatedAt
                                 updated_at createdAt created_at].freeze
          # Preferred keys when extracting category-like values from state payloads.
          CATEGORY_KEYS = %i[categories tags section sections topic topics channel].freeze
          # Preferred keys when extracting identifier-like values from state payloads.
          ID_KEYS = %i[id guid uuid slug key].freeze
          # Max times to unwrap a Hash URL value (e.g. path.alias, links.self.href).
          MAX_URL_UNWRAP = 3
          # Nested title/description keys (WordPress +rendered+, CMS +value+/+text+).
          SCALAR_KEYS = %i[rendered value text].freeze
          # Snake `_at`/`_on` or camel `At`/`On` suffix after a closed published-at miss.
          DATE_KEY_SUFFIX = /_at\z|_on\z|[a-z]At\z|[a-z]On\z/

          module_function

          # rubocop:disable Metrics/MethodLength
          # @param entry [Hash] raw article entry candidate
          # @param base_url [String, Html2rss::Url] base URL for relative link resolution
          # @return [Hash{Symbol => Object, nil}] normalized article hash for downstream extraction
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
              published_at: published_at(entry),
              categories: categories(entry),
              id: identifier(entry, article_url)
            }.compact
          end
          # rubocop:enable Metrics/MethodLength

          # @param value [Object] candidate scalar, or Hash wrapping +rendered+/+value+/+text+
          # @return [String, nil] normalized non-empty string (HTML preserved for descriptions)
          def string(value)
            value = unwrap_scalar(value)
            return unless value.is_a?(String) || value.is_a?(Numeric)

            trimmed = value.to_s.strip
            trimmed unless trimmed.empty?
          end

          # @param value [Object] candidate scalar or nested Hash
          # @return [Object, nil] String/Numeric after at most {MAX_URL_UNWRAP} Hash unwraps
          def unwrap_scalar(value)
            depth = 0
            while value.is_a?(Hash) && depth < MAX_URL_UNWRAP
              nested = SCALAR_KEYS.find { |key| value.key?(key) }
              break unless nested

              value = value[nested]
              depth += 1
            end
            value unless value.is_a?(Hash) || value.is_a?(Array)
          end

          # @param entry [Hash] raw article entry candidate
          # @param keys [Array<Symbol>] preferred link keys
          # @param base_url [String, Html2rss::Url] base URL for relative link resolution
          # @param log_key [String] structured log message key
          # @return [Html2rss::Url, nil] resolved absolute URL
          def resolve_link(entry, keys:, base_url:, log_key:)
            value = unwrap_url(ValueFinder.fetch(entry, keys), keys) ||
                    unwrap_url(ValueFinder.fetch(entry[:links], keys), keys)
            string = string(value)
            return unless string

            Url.from_relative(string, base_url)
          rescue ArgumentError
            Log.debug("#{log_key}: url=#{string}")
            nil
          end

          # @param value [Object] candidate URL value, possibly a nested Hash
          # @param keys [Array<Symbol>] preferred link keys
          # @return [Object, nil] scalar URL candidate after at most {MAX_URL_UNWRAP} Hash unwraps
          def unwrap_url(value, keys)
            depth = 0
            while value.is_a?(Hash) && depth < MAX_URL_UNWRAP
              value = ValueFinder.fetch(value, keys)
              depth += 1
            end
            value unless value.is_a?(Hash)
          end

          # @param entry [Hash] raw article entry candidate
          # @return [String, nil] publication timestamp string or unix timestamp digits
          def published_at(entry)
            value = ValueFinder.fetch(entry, PUBLISHED_AT_KEYS)
            string(value) || string(suffix_date_value(entry))
          end

          # @param hash [Hash, nil] entry or nested attributes/data hash
          # @return [Object, nil] first string or numeric value whose key matches {DATE_KEY_SUFFIX}
          def suffix_date_value(hash)
            return unless hash.is_a?(Hash)

            hash.each do |key, value|
              next unless date_suffix_key?(key)
              next unless value.is_a?(String) || value.is_a?(Numeric)

              return value
            end

            suffix_date_value(hash[:attributes]) || suffix_date_value(hash[:data])
          end

          # @param key [Symbol, String] candidate published-at key
          # @return [Boolean] whether the key ends in a date suffix (_at/_on/At/On)
          def date_suffix_key?(key)
            key.to_s.match?(DATE_KEY_SUFFIX)
          end

          # rubocop:disable Metrics/MethodLength
          # @param entry [Hash] raw article entry candidate
          # @return [Array<String>, nil] normalized unique categories
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
                string(ValueFinder.fetch(value, %i[name title label]))
              else
                string(value)
              end
            end.compact

            result.uniq!
            result unless result.empty?
          end
          # rubocop:enable Metrics/MethodLength

          # @param entry [Hash] raw article entry candidate
          # @param article_url [Html2rss::Url] resolved article URL
          # @return [String] stable article identifier fallbacking to resolved URL
          def identifier(entry, article_url)
            value = ValueFinder.fetch(entry, ID_KEYS)
            value = ValueFinder.fetch(value, ID_KEYS) if value.is_a?(Hash)
            string(value) || article_url.to_s
          end
        end
      end
    end
  end
end
