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

          # @param schema_object [Hash{Symbol => Object}] parsed schema.org object
          # @param url [String, Html2rss::Url, nil] base URL used for relative normalization
          def initialize(schema_object, url:)
            @schema_object = schema_object
            @base_url = normalized_base_url(url)
          end

          # @return [Hash{Symbol => Object}] scraped article attributes
          def call
            { id:, title:, description:, author:, url:, image:, published_at:, categories: }
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
            extract_author_name(schema_object[:author]) || extract_author_name(schema_object[:publisher])
          end

          # @return [Html2rss::Url, nil] the URL of the schema object
          def url
            return @url if defined?(@url)

            @url = build_url(first_scalar(schema_object[:url]))
          end

          # @return [Html2rss::Url, nil] normalized article image URL
          def image
            return @image if defined?(@image)

            img_url = image_urls.first
            @image = img_url ? Url.from_relative(img_url, base_url || img_url) : nil
          end

          # @return [String, nil] first non-empty of datePublished, dateCreated, dateModified, uploadDate
          def published_at
            schema_object.values_at(:datePublished, :dateCreated, :dateModified, :uploadDate)
                         .map { first_scalar(_1) }
                         .find { !_1.to_s.empty? }
          end

          # @return [Array<String>, nil] extracted category labels
          def categories
            @categories ||= CategoryExtractor.call(schema_object)
          end

          attr_reader :schema_object, :base_url

          # @return [Array<String>] normalized image URL candidates
          def image_urls
            @image_urls ||= schema_object.values_at(:image, :thumbnailUrl).filter_map { image_url_from(_1) }
          end

          private

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
            return unless Schema.normalize_types(obj[:@type]).include?('ImageObject')

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
