# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # Shared category term vocabulary and text accumulation (DOM walk stays in adapters).
      module Category
        # Class/data attribute tokens that mark category metadata.
        CATEGORY_TERMS = %w[
          category categories tag tags topic topics section sections
          label labels theme themes subject subjects
        ].freeze

        # Regex matching category-related attribute or class names.
        CATEGORY_ATTR_PATTERN = /#{CATEGORY_TERMS.join('|')}/i

        class << self
          ##
          # @param name [String]
          # @return [Boolean]
          def attr_name_match?(name)
            name.to_s.match?(CATEGORY_ATTR_PATTERN)
          end

          ##
          # @param class_attr [String, nil]
          # @return [Boolean]
          def class_match?(class_attr)
            class_attr.to_s.match?(CATEGORY_ATTR_PATTERN)
          end

          ##
          # @param categories [Set<String>]
          # @param text [String, nil]
          # @return [void]
          def add_text!(categories, text)
            value = text.to_s.strip
            categories.add(value) unless value.empty?
          end

          ##
          # @param categories [Set<String>]
          # @param text [String, nil]
          # @return [void]
          def add_split_text!(categories, text)
            return unless text

            text.split(/\n+/).each { |line| add_text!(categories, line) }
          end
        end
      end
    end
  end
end
