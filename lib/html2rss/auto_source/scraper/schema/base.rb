# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        # Base class for Schema.org schema_objects.
        #
        # @see https://schema.org/Article
        class Base
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

          def id = schema_object[:@id] || url&.path || title.to_s.downcase.gsub(/\s+/, '-')
          def title = schema_object[:title]

          def description
            [schema_object[:description], schema_object[:schema_object_body], schema_object[:abstract]]
              .max_by { |desc| desc.to_s.size }
          end

          # @return [Addressable::URI, nil] the URL of the schema object
          def url
            url = schema_object[:url]
            if url.to_s.empty?
              Log.debug("Schema#Base.url: no url in schema_object: #{schema_object.inspect}")
              return
            end

            Utils.build_absolute_url_from_relative(url, @url)
          end

          def image = images.first || nil
          def published_at = schema_object[:datePublished]

          private

          attr_reader :schema_object

          def images
            Array(schema_object[:image]).compact
          end
        end
      end
    end
  end
end
