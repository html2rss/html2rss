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
        class Thing
          SUPPORTED_TYPES = %w[
            AdvertiserContentArticle
            AnalysisNewsArticle
            APIReference
            Article
            AskPublicNewsArticle
            BackgroundNewsArticle
            BlogPosting
            DiscussionForumPosting
            LiveBlogPosting
            NewsArticle
            OpinionNewsArticle
            Report
            ReportageNewsArticle
            ReviewNewsArticle
            SatiricalArticle
            ScholarlyArticle
            SocialMediaPosting
            TechArticle
          ].to_set.freeze

          DEFAULT_ATTRIBUTES = %i[id title description url image published_at].freeze

          def initialize(schema_object, url:)
            @schema_object = schema_object
            @url = url
          end

          # @return [Hash] the scraped article hash with DEFAULT_ATTRIBUTES
          def call
            DEFAULT_ATTRIBUTES.to_h do |attribute|
              [attribute, public_send(attribute)]
            end
          end

          def id
            return @id if defined?(@id)

            id = (schema_object[:@id] || url&.path).to_s

            return if id.empty?

            @id = id
          end

          def title = schema_object[:title]

          def description
            schema_object.values_at(:description, :schema_object_body, :abstract)
                         .max_by { |string| string.to_s.size }
          end

          # @return [Addressable::URI, nil] the URL of the schema object
          def url
            url = schema_object[:url]
            if url.to_s.empty?
              Log.debug("Schema#Thing.url: no url in schema_object: #{schema_object.inspect}")
              return
            end

            Utils.build_absolute_url_from_relative(url, @url)
          end

          def image
            if (image_url = image_urls.first)
              Utils.build_absolute_url_from_relative(image_url, @url)
            end
          end

          def published_at = schema_object[:datePublished]

          private

          attr_reader :schema_object

          def image_urls
            schema_object.values_at(:image, :thumbnailUrl).filter_map do |object|
              next unless object

              if object.is_a?(String)
                object
              elsif object.is_a?(Hash) && object[:@type] == 'ImageObject'
                object[:url] || object[:contentUrl]
              end
            end
          end
        end
      end
    end
  end
end
