# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Shapes raw entries into the structure required downstream.
        module ArticleNormalizer # rubocop:disable Metrics/ModuleLength -- field keys + URL/scalar unwrap stay co-located
          # Preferred keys when extracting title-like values from state payloads.
          TITLE_KEYS = %i[title headline name text].freeze
          # Title keys that mark an article; a bare +name+ also labels people and other entities.
          ARTICLE_TITLE_KEYS = (TITLE_KEYS - %i[name]).freeze
          # Explicit kicker field names (app-state +overline+/+kickerText+, German CMS +topline+/+dachzeile+) that
          # sit beside a headline. The one closed list: no standard Schema/JSON-LD field exists, so none is guessed.
          KICKER_KEYS = %i[overline kicker kickerText topline dachzeile eyebrow].freeze
          # Preferred keys when extracting URL-like values from state payloads.
          URL_KEYS = %i[url link href permalink slug path canonicalUrl shortUrl alias self links].freeze
          # URL keys an entry itself can own; +links+ is an envelope sibling of the node, never the entry's own URL.
          DIRECT_URL_KEYS = (URL_KEYS - %i[links]).freeze
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
          # Levels below a wrapper entry searched for its article node.
          MAX_NODE_DEPTH = 2

          class << self
            # rubocop:disable Metrics/MethodLength
            # @param entry [Hash] raw article entry candidate
            # @param base_url [String, Html2rss::Url] base URL for relative link resolution
            # @return [Hash{Symbol => Object, nil}] normalized article hash for downstream extraction
            def normalise(entry, base_url:)
              sources = article_sources(entry) # nil (skipped entry) yields no URL below
              title = string(ValueFinder.fetch(sources, TITLE_KEYS))
              kicker = title && string(ValueFinder.fetch(sources, KICKER_KEYS))
              description = string(ValueFinder.fetch(sources, DESCRIPTION_KEYS))
              article_url = resolve_link(sources, keys: URL_KEYS, base_url:,
                                                  log_key: 'JsonState: invalid URL encountered')
              return unless article_url
              return if title.nil? && description.nil?

              {
                title:,
                kicker:,
                description:,
                url: article_url,
                image: resolve_link(sources, keys: IMAGE_KEYS, base_url:,
                                             log_key: 'JsonState: invalid image URL encountered'),
                published_at: published_at(sources),
                categories: categories(sources),
                id: identifier(sources, article_url)
              }.compact
            end
            # rubocop:enable Metrics/MethodLength

            # Locates the hashes holding an entry's article fields, article node first.
            #
            # An entry with its own title or description is its own article node. A wrapper entry
            # delegates to the only nested Hash (up to {MAX_NODE_DEPTH} levels down) carrying a title
            # and URL, else to the only nested Hash carrying a title; the entry stays the fallback
            # source (e.g. an envelope's sibling +links+). A wrapper entry with its own URL is the
            # link: it delegates only to the only nested Hash carrying an article title (never a bare
            # +name+), and its URL wins over the node's. An entry whose only URL is +links+ is not that
            # link: the node leads and +links+ stays a fallback. Competing nested nodes skip the entry, so an
            # author object holding a name and URL never becomes the article.
            #
            # @param entry [Object] raw article entry candidate
            # @return [Array<Hash>, nil] field sources in lookup order; nil when not a Hash or ambiguous
            def article_sources(entry)
              return unless entry.is_a?(Hash)
              return [entry] if text?(entry)

              nodes = candidate_nodes(entry)
              return [entry] if nodes.empty?
              return unless nodes.one?

              node = nodes.first
              own_url?(entry) && url?(node) ? [entry, node] : [node, entry]
            end

            # @param sources [Hash, Array<Hash>, nil] entry or field sources from {article_sources}
            # @return [Boolean] whether the sources hold a title and a URL value
            def linked?(sources)
              title?(sources) && url?(sources)
            end

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

            # @param sources [Hash, Array<Hash>] entry or field sources from {article_sources}
            # @param keys [Array<Symbol>] preferred link keys
            # @param base_url [String, Html2rss::Url] base URL for relative link resolution
            # @param log_key [String] structured log message key
            # @return [Html2rss::Url, nil] resolved absolute URL
            def resolve_link(sources, keys:, base_url:, log_key:)
              string = string(unwrap_url(ValueFinder.fetch(sources, keys), keys))
              return unless string

              Url.from_relative(string, base_url)
            rescue Html2rss::Url::InvalidUrlError
              Log.debug("#{log_key}: url=#{string}")
              nil
            end

            # @param value [Object] candidate URL value, possibly a nested Hash or a links Array
            # @param keys [Array<Symbol>] preferred link keys
            # @return [Object, nil] scalar URL candidate after at most {MAX_URL_UNWRAP} unwraps
            def unwrap_url(value, keys)
              depth = 0
              while (value.is_a?(Hash) || value.is_a?(Array)) && depth < MAX_URL_UNWRAP
                value = ValueFinder.fetch(value, keys)
                depth += 1
              end
              value unless value.is_a?(Hash) || value.is_a?(Array)
            end

            # @param sources [Hash, Array<Hash>] entry or field sources from {article_sources}
            # @return [String, nil] publication timestamp string or unix timestamp digits
            def published_at(sources)
              value = ValueFinder.fetch(sources, PUBLISHED_AT_KEYS)
              string(value) || string(suffix_date_value(sources))
            end

            # @param sources [Hash, Array<Hash>, nil] entry or field sources, searched in order
            # @return [Object, nil] first string or numeric value whose key matches {DATE_KEY_SUFFIX}
            def suffix_date_value(sources)
              case sources
              when Hash
                sources.each do |key, value|
                  return value if date_suffix_key?(key) && (value.is_a?(String) || value.is_a?(Numeric))
                end
                nil
              when Array then sources.filter_map { suffix_date_value(_1) }.first
              end
            end

            # @param key [Symbol, String] candidate published-at key
            # @return [Boolean] whether the key ends in a date suffix (_at/_on/At/On)
            def date_suffix_key?(key)
              key.to_s.match?(DATE_KEY_SUFFIX)
            end

            # rubocop:disable Metrics/MethodLength
            # @param sources [Hash, Array<Hash>] entry or field sources from {article_sources}
            # @return [Array<String>, nil] normalized unique categories
            def categories(sources)
              raw = ValueFinder.fetch(sources, CATEGORY_KEYS)
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

            # @param sources [Hash, Array<Hash>] entry or field sources from {article_sources}
            # @param article_url [Html2rss::Url] resolved article URL
            # @return [String] stable article identifier fallbacking to resolved URL
            def identifier(sources, article_url)
              value = ValueFinder.fetch(sources, ID_KEYS)
              value = ValueFinder.fetch(value, ID_KEYS) if value.is_a?(Hash)
              string(value) || article_url.to_s
            end

            private

            # Shape checks (key holds a value), not usability checks: normalise decides usability.
            def text?(hash)
              title?(hash) || !ValueFinder.fetch(hash, DESCRIPTION_KEYS).nil?
            end

            def title?(object)
              !ValueFinder.fetch(object, TITLE_KEYS).nil?
            end

            def url?(object)
              !ValueFinder.fetch(object, URL_KEYS).nil?
            end

            def own_url?(entry)
              !ValueFinder.fetch(entry, DIRECT_URL_KEYS).nil?
            end

            # Nested nodes that may hold the article fields of a wrapper entry.
            def candidate_nodes(entry)
              titled = titled_nodes(entry, MAX_NODE_DEPTH)
              return titled.reject { ValueFinder.fetch(_1, ARTICLE_TITLE_KEYS).nil? } if own_url?(entry)

              linked = titled.select { url?(_1) }
              linked.empty? ? titled : linked
            end

            # Titled Hash values up to +depth+ levels down; a titled node's children are its own fields.
            def titled_nodes(hash, depth)
              return [] if depth.zero?

              hash.each_value.flat_map do |value|
                next [] unless value.is_a?(Hash)
                next value if title?(value)

                titled_nodes(value, depth - 1)
              end
            end
          end
        end
      end
    end
  end
end
