# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # Shared category term vocabulary and text accumulation (DOM walk stays in adapters).
      module Category
        # Class/data attribute tokens that mark category metadata (not layout words).
        CATEGORY_TERMS = %w[
          category categories tag tags topic topics
          theme themes subject subjects
        ].freeze

        # Frozen set for token membership checks.
        TERM_SET = CATEGORY_TERMS.to_set.freeze

        # Hyphen/underscore/BEM separators inside a single CSS class token.
        CLASS_TOKEN_SPLIT = /[-_]+/

        class << self
          ##
          # @param name [String]
          # @return [Boolean]
          def attr_name_match?(name)
            TERM_SET.include?(normalize_attr_name(name))
          end

          ##
          # @param class_attr [String, nil]
          # @return [Boolean]
          def class_match?(class_attr)
            class_attr.to_s.split(/\s+/).any? { |token| class_token_match?(token) }
          end

          ##
          # @param categories [Set<String>]
          # @param text [String, nil]
          # @param title [String, nil]
          # @return [void]
          def add_text!(categories, text, title: nil)
            value = text.to_s.strip
            return if value.empty? || !Description.keep?(value, title:, type_chips: false)

            categories.add(value)
          end

          ##
          # @param categories [Set<String>]
          # @param text [String, nil]
          # @param title [String, nil]
          # @return [void]
          def add_split_text!(categories, text, title: nil)
            return unless text

            text.split(/\n+/).each { |line| add_text!(categories, line, title:) }
          end

          private

          def class_token_match?(token)
            token.downcase.split(CLASS_TOKEN_SPLIT).intersect?(CATEGORY_TERMS)
          end

          def normalize_attr_name(name)
            name.to_s.downcase.delete_prefix('data-')
          end
        end
      end
    end
  end
end
