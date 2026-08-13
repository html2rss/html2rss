# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Shapes raw entries into the structure required downstream.
        module ArticleNormalizer
          # Preferred keys when extracting title-like values from state payloads.
          TITLE_KEYS = %i[title headline name text].freeze
          # Preferred keys when extracting URL-like values from state payloads.
          URL_KEYS = %i[url link href permalink slug path canonicalUrl shortUrl].freeze
          # Preferred keys when extracting description-like values from state payloads.
          DESCRIPTION_KEYS = %i[description summary excerpt dek subheading].freeze
          # Preferred keys when extracting image-like values from state payloads.
          IMAGE_KEYS = %i[image imageUrl thumbnailUrl thumbnail src featuredImage coverImage heroImage].freeze
          # Preferred keys when extracting publication timestamps from state payloads.
          PUBLISHED_AT_KEYS = %i[published_at publishedAt datePublished date publicationDate pubDate updatedAt
                                 updated_at createdAt created_at].freeze
          # Preferred keys when extracting category-like values from state payloads.
          CATEGORY_KEYS = %i[categories tags section sections topic topics channel].freeze
          # Preferred keys when extracting identifier-like values from state payloads.
          ID_KEYS = %i[id guid uuid slug key].freeze

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
              published_at: string(ValueFinder.fetch(entry, PUBLISHED_AT_KEYS)),
              categories: categories(entry),
              id: identifier(entry, article_url)
            }.compact
          end
          # rubocop:enable Metrics/MethodLength

          # @param value [Object] candidate scalar value
          # @return [String, nil] normalized non-empty string value
          def string(value)
            trimmed = value.to_s.strip
            trimmed unless trimmed.empty?
          end

          # @param entry [Hash] raw article entry candidate
          # @param keys [Array<String>] preferred link keys
          # @param base_url [String, Html2rss::Url] base URL for relative link resolution
          # @param log_key [String] structured log message key
          # @return [Html2rss::Url, nil] resolved absolute URL
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
