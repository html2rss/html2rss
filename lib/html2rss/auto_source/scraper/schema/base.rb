# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        # Base class for Schema.org schema_objects.
        #
        # To add more attributes:
        # 1. Create a subclass
        # 2. Override `#specific_attributes`
        # 3. For each specific attribute, define a method that returns the desired value.
        # 4. Add the subclass to Schema::schema_object_TYPES and Schema#scraper_from_schema_object.
        class Base
          def initialize(schema_object, url:)
            @schema_object = schema_object
            @url = url
            @attributes = %i[id title description url image published_at] + specific_attributes
          end

          # @return [Hash] the scraped article_hash
          def call
            @attributes.to_h do |attribute, _|
              [attribute, public_send(attribute)]
            end
          end

          def id = schema_object[:@id] || url&.path || title.to_s.downcase.gsub(/\s+/, '-')
          def title = schema_object[:title]

          def description
            [
              schema_object[:description], schema_object[:schema_object_body], schema_object[:abstract
              ]
            ].max_by { |desc| desc.to_s.size }
          end

          # @return [Adressable::URI, nil] the URL of the schema_object
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

          def images = [schema_object[:image]].flatten.compact

          # @return [Array<Symbol>] addition attributes for specific type (override in subclass)
          def specific_attributes
            []
          end
        end
      end
    end
  end
end
