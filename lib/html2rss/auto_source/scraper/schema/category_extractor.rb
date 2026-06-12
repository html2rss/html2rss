# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        # Extracts categories from Schema.org structured data.
        module CategoryExtractor
          ##
          # Extracts categories from a schema object.
          #
          # @param schema_object [Hash] The schema object
          # @return [Array<String>] Array of category strings
          def self.call(schema_object)
            Set.new.tap do |categories|
              extract_field_categories!(categories, schema_object)
              extract_about_categories!(categories, schema_object)
            end.to_a
          end

          ##
          # Extracts categories from keywords, categories, and tags fields.
          #
          # @param schema_object [Hash] The schema object
          # @return [Set<String>] Set of category strings
          def self.extract_field_categories(schema_object)
            Set.new.tap { |categories| extract_field_categories!(categories, schema_object) }
          end

          ##
          # Extracts categories from keywords, categories, and tags fields.
          #
          # @param categories [Set<String>] Accumulator set
          # @param schema_object [Hash] The schema object
          # @return [void]
          def self.extract_field_categories!(categories, schema_object)
            %i[keywords categories tags].each do |field|
              extract_field_value!(categories, schema_object[field])
            end
          end

          ##
          # Extracts categories from the about field.
          #
          # @param schema_object [Hash] The schema object
          # @return [Set<String>] Set of category strings
          def self.extract_about_categories(schema_object)
            Set.new.tap { |categories| extract_about_categories!(categories, schema_object) }
          end

          ##
          # Extracts categories from the about field.
          #
          # @param categories [Set<String>] Accumulator set
          # @param schema_object [Hash] The schema object
          # @return [void]
          def self.extract_about_categories!(categories, schema_object)
            about = schema_object[:about]
            return unless about

            if about.is_a?(Array)
              extract_about_array!(categories, about)
            elsif about.is_a?(String)
              extract_string_categories!(categories, about)
            end
          end

          ##
          # Extracts categories from a single field value.
          #
          # @param schema_object [Hash] The schema object
          # @param field [String] The field name
          # @return [Set<String>] Set of category strings
          def self.extract_field_value(schema_object, field)
            Set.new.tap { |categories| extract_field_value!(categories, schema_object[field.to_sym]) }
          end

          ##
          # Extracts categories from a single field value.
          #
          # @param categories [Set<String>] Accumulator set
          # @param value [Object] The field value
          # @return [void]
          def self.extract_field_value!(categories, value)
            return unless value

            if value.is_a?(Array)
              value.each do |item|
                s = item.to_s
                categories.add(s) unless s.empty?
              end
            elsif value.is_a?(String)
              extract_string_categories!(categories, value)
            end
          end

          ##
          # Extracts categories from an about array.
          #
          # @param about [Array] The about array
          # @return [Set<String>] Set of category strings
          def self.extract_about_array(about)
            Set.new.tap { |categories| extract_about_array!(categories, about) }
          end

          ##
          # Extracts categories from an about array.
          #
          # @param categories [Set<String>] Accumulator set
          # @param about [Array] The about array
          # @return [void]
          def self.extract_about_array!(categories, about)
            about.each do |item|
              if item.is_a?(Hash) && item[:name]
                categories.add(item[:name].to_s)
              elsif item.is_a?(String)
                categories.add(item)
              end
            end
          end

          ##
          # Extracts categories from a string by splitting on separators.
          #
          # @param string [String] source string that may contain category delimiters
          # @return [Set<String>] Set of category strings
          def self.extract_string_categories(string)
            Set.new.tap { |categories| extract_string_categories!(categories, string) }
          end

          ##
          # Extracts categories from a string by splitting on separators.
          #
          # @param categories [Set<String>] Accumulator set
          # @param string [String] source string that may contain category delimiters
          # @return [void]
          def self.extract_string_categories!(categories, string)
            string.split(/[,;|]/).each do |part|
              s = part.strip
              categories.add(s) unless s.empty?
            end
          end
        end
      end
    end
  end
end
