# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        # A Thing is kind of the 'base class' for Schema.org schema_objects.
        #
        # @see https://schema.org/Thing
        class Thing # rubocop:disable Metrics/ClassLength -- one accessor per schema.org field
          # Supported Schema.org `@type` values mapped to article extraction.
          SUPPORTED_TYPES = %w[
            AdvertiserContentArticle AnalysisNewsArticle APIReference Article
            AskPublicNewsArticle BackgroundNewsArticle BlogPosting DiscussionForumPosting
            LiveBlogPosting NewsArticle OpinionNewsArticle Report ReportageNewsArticle
            ReviewNewsArticle SatiricalArticle ScholarlyArticle SocialMediaPosting TechArticle
          ].to_set.freeze

          # Schema.org media types and the file kind each proves (`contentUrl` is the file, `embedUrl` the
          # player), so an untyped `contentUrl` without a media extension is still audio or video.
          MEDIA_KINDS = {
            'AudioObject' => :audio, 'PodcastEpisode' => :audio, 'VideoObject' => :video, 'Clip' => :video
          }.freeze

          # Schema.org media types: items wherever they appear (standalone, in `@graph` or an array, as ItemList
          # elements), marked `media: true`; their own `contentUrl` (when present) is a media enclosure.
          MEDIA_TYPES = MEDIA_KINDS.keys.to_set.freeze

          # Types emitted as items wherever they appear: articles and media.
          ITEM_TYPES = (SUPPORTED_TYPES | MEDIA_TYPES).freeze

          # Keys holding the media objects (object or array) whose `contentUrl` is an enclosure, in choice order.
          MEDIA_KEYS = %i[video audio associatedMedia].freeze

          # A MIME type (`type/subtype`) at the start of `encodingFormat`; a bare format name such as `mp3` maps
          # through {Article::Enclosure::MEDIA_TYPES}.
          MIME_TYPE = %r{\A[a-z]+/[a-z0-9][\w.+-]*}i

          # Schema.org entity types that describe who or what something is, never a piece of content; a
          # ListItem-wrapped object typed only with these is not a feed item. Organization and Place subtypes
          # are listed because the wire form carries the subtype, not the parent.
          ENTITY_TYPES = Set[
            'Person',
            'Organization', 'Corporation', 'NGO', 'LocalBusiness', 'GovernmentOrganization',
            'EducationalOrganization', 'NewsMediaOrganization', 'Brand',
            'Product', 'ProductGroup', 'Offer',
            'Place', 'City', 'Country', 'PostalAddress'
          ].freeze

          # Schema.org types emitted only as elements of an ItemList (never standalone).
          ITEM_LIST_TYPES = Set['Event', 'JobPosting'].freeze

          # @param schema_object [Hash{Symbol => Object}] parsed schema.org object
          # @param url [String, Html2rss::Url, nil] base URL used for relative normalization
          def initialize(schema_object, url:)
            @schema_object = schema_object
            @base_url = normalized_base_url(url)
          end

          # @return [Hash{Symbol => Object}] scraped article attributes; a media object's carry `media: true`
          def call
            item = { id:, title:, description:, author:, url:, image:, published_at:, categories:, enclosures: }
            own_media? ? item.merge(media: true) : item
          end

          # @return [String, nil] stable schema object identifier
          def id
            return @id if defined?(@id)

            id = normalized_id(schema_object[:@id], reference_url: url || base_url) || url&.path.to_s
            @id = id.to_s.empty? ? nil : id
          end

          # @return [String, nil] article title (schema.org: headline → name → alternativeHeadline; legacy title)
          def title
            schema_object.values_at(:headline, :name, :alternativeHeadline, :title)
                         .lazy
                         .map { first_scalar(_1).to_s.strip }
                         .find { !_1.empty? }
          end

          # @return [String, nil] longest available description field
          def description
            schema_object.values_at(:description, :articleBody, :abstract, :schema_object_body)
                         .map { first_scalar(_1) }
                         .max_by { _1.to_s.size }
          end

          # @return [String, nil] extracted author or publisher name
          def author
            extract_author_name(schema_object[:author]) || extract_author_name(schema_object[:publisher]) ||
              extract_author_name(schema_object[:hiringOrganization]) ||
              extract_author_name(schema_object[:organizer])
          end

          # @return [Html2rss::Url, nil] the URL of the schema object
          def url
            return @url if defined?(@url)

            @url = build_url(first_scalar(schema_object[:url])) || fallback_url
          end

          # @return [Html2rss::Url, nil] normalized article image URL
          def image
            return @image if defined?(@image)

            img_url = image_urls.first
            @image = img_url ? Url.from_relative(img_url, base_url || img_url) : nil
          end

          # @return [String, nil] first non-empty of datePublished, datePosted, dateCreated, dateModified, uploadDate
          def published_at
            schema_object.values_at(:datePublished, :datePosted, :dateCreated, :dateModified, :uploadDate)
                         .map { first_scalar(_1) }
                         .find { !_1.to_s.empty? }
          end

          # @return [Array<String>, nil] extracted category labels
          def categories
            @categories ||= CategoryExtractor.call(schema_object)
          end

          # @return [Array<Hash{Symbol => Object}>, nil] enclosures from the `contentUrl` of nested media objects
          #   ({MEDIA_KEYS}) and of a media object itself, with declared size and duration; `embedUrl` is never one
          def enclosures
            nodes = schema_object.values_at(*MEDIA_KEYS).flatten
            nodes << schema_object if own_media?
            found = nodes.filter_map { media_enclosure(_1) }
            found unless found.empty?
          end

          attr_reader :schema_object, :base_url

          # @return [Array<String>] normalized image URL candidates
          def image_urls
            @image_urls ||= schema_object.values_at(:image, :thumbnailUrl, :thumbnail).filter_map { image_url_from(_1) }
          end

          private

          # @return [Boolean] whether the object itself is a media object (an item marked media)
          def own_media? = Schema.normalize_types(schema_object[:@type]).intersect?(MEDIA_TYPES)

          # @param node [Object] media object (VideoObject, AudioObject, MediaObject) or the media item itself
          # @return [Hash{Symbol => Object}, nil] enclosure attributes, or nil without an http(s) contentUrl
          #   (an ImageObject is never one: images are {#image})
          def media_enclosure(node)
            return unless node.is_a?(Hash) && (src = first_scalar(node[:contentUrl])).is_a?(String)
            return if (types = Schema.normalize_types(node[:@type])).include?('ImageObject')

            kind = types.filter_map { MEDIA_KINDS[_1] }.first
            type = mime_type(node[:encodingFormat])
            Html2rss::Html::ArticleRules::Enclosure.from_media(src, type, base_url, kind:)&.merge(file_facts(node))
          end

          # @param node [Hash] media object
          # @return [Hash{Symbol => Integer, nil}] its byte length and playback seconds, the duration else that of
          #   the item itself (a PodcastEpisode's duration)
          def file_facts(node)
            duration = Article::Enclosure.parse_duration(node[:duration]) ||
                       Article::Enclosure.parse_duration(schema_object[:duration])
            { bytes_length: Article::Enclosure.parse_size(node[:contentSize]), duration: }
          end

          # @param format [Object] encodingFormat
          # @return [String, nil] its lowercase MIME type, or the playable type of a media format name (+mp3+,
          #   +.m4a+); nil for any other name, so the file name decides
          def mime_type(format)
            return unless format.is_a?(String)

            format[MIME_TYPE]&.downcase || Article::Enclosure::MEDIA_TYPES[format.strip.downcase.delete_prefix('.')]
          end

          # @param value [Object] url candidate
          # @return [Html2rss::Url, nil] absolute url, or nil when missing or unusable
          def build_url(value)
            return Url.from_relative(value, base_url || value) if value.is_a?(String) && !value.empty?

            Log.debug("Schema#Thing.url: no usable url in schema_object: #{schema_object.inspect}")
            nil
          rescue Url::InvalidUrlError
            Log.debug("Schema#Thing.url: unusable url #{value.inspect}")
            nil
          end

          # @return [Html2rss::Url, nil] first absolute http(s) mainEntityOfPage, @id or embedUrl (a player page,
          #   last), without fragment; never `contentUrl`, which is a file
          def fallback_url
            main = schema_object[:mainEntityOfPage]
            candidates = main.is_a?(Hash) ? [main[:@id], main[:url]] : [main]
            (candidates + schema_object.values_at(:@id, :embedUrl)).lazy.filter_map { web_url(_1) }.first
          end

          # @param value [Object] url candidate
          # @return [Html2rss::Url, nil] fragment-free url when value is an absolute http(s) string
          def web_url(value)
            return unless value.is_a?(String) && value.match?(%r{\Ahttps?://}i)

            Url.from_absolute(value.strip).without_fragment
          rescue Url::InvalidUrlError
            nil
          end

          # @param value [Object] schema value that may be wrapped in a list (multilingual or multi-valued fields)
          # @return [Object, nil] the value, or the first non-empty String of a list
          def first_scalar(value)
            return value unless value.is_a?(Array)

            value.find { _1.is_a?(String) && !_1.strip.empty? }
          end

          # @param obj [String, Hash, Array, nil] schema author or publisher field
          # @return [String, nil] extracted author name
          def extract_author_name(obj)
            case obj
            when String then obj.strip unless obj.strip.empty?
            when Hash then obj[:name].to_s.strip unless obj[:name].to_s.strip.empty?
            when Array
              names = obj.filter_map { extract_author_name(_1) }
              names.join(', ') unless names.empty?
            end
          end

          # @param obj [String, Hash, Array, nil] image node or list of image nodes
          # @return [String, nil] image URL string (first usable entry for lists)
          def image_url_from(obj)
            return obj if obj.is_a?(String)
            return obj.filter_map { image_url_from(_1) }.first if obj.is_a?(Array)
            return unless obj.is_a?(Hash)

            types = Schema.normalize_types(obj[:@type])
            return unless types.empty? || types.include?('ImageObject')

            obj[:url] || obj[:contentUrl]
          end

          # @param value [String, Symbol, nil] candidate schema identifier
          # @param reference_url [Html2rss::Url, nil] URL used for same-origin normalization
          # @return [String, nil] normalized identifier value
          def normalized_id(value, reference_url:)
            text = value.to_s
            return if text.empty?

            norm_url = normalized_id_url(text, reference_url:)
            reference_url && norm_url.host == reference_url.host ? normalized_id_value(norm_url) : text
          rescue Html2rss::Url::InvalidUrlError
            text
          end

          # @param text [String] raw identifier text
          # @param reference_url [Html2rss::Url, nil] URL used to resolve relative IDs
          # @return [Html2rss::Url] normalized identifier URL
          def normalized_id_url(text, reference_url:)
            text.start_with?('/') ? Url.from_relative(text, reference_url || text) : Url.from_absolute(text)
          end

          # @param url [Html2rss::Url] normalized identifier URL
          # @return [String, nil] path/query portion used as stable ID
          def normalized_id_value(url)
            path = url.path.to_s
            return "#{path}?#{url.query}" if (path.empty? || path == '/') && !url.query.to_s.empty?

            path.empty? ? url.query : path
          end

          # @param url [String, Html2rss::Url, nil] candidate page URL
          # @return [Html2rss::Url, nil] normalized absolute URL for schema resolution
          def normalized_base_url(url)
            Url.from_absolute(url) unless url.to_s.strip.empty?
          rescue Html2rss::Url::InvalidUrlError
            nil
          end
        end
      end
    end
  end
end
