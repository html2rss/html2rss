# frozen_string_literal: true

module Html2rss
  class AutoSource
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

        # A file-size label ("PDF 265 KB").
        FILE_SIZE = /\d(?:[.,]\d+)?\s*(?:[KMGT]i?B|bytes?)\b/i

        # A separator that sets a piece apart inside one category value ("Topic // 2026-11-26").
        PIECE_SEPARATOR = %r{\s+(?://?|[|·•–—-])\s+}

        # Fewest items for which a shared value is a feed-wide label; with two, it may be a real topic.
        MIN_ITEMS_FOR_SHARED = 3

        # Text cut off by the page ("Forschung und Ent...").
        CUT_OFF = /(?:\.\.\.|…)\z/

        class << self
          ##
          # @param value [String] a stripped category candidate
          # @param title [String, nil] headline whose text before a colon is not a category
          # @return [Boolean] whether the value is a file-size label, holds a date, is cut off, or is the
          #   title's own prefix before a colon ("Topic: rest of title")
          def junk?(value, title: nil)
            [FILE_SIZE, CUT_OFF].any? { |pattern| value.match?(pattern) } ||
              dated?(value) || title_prefix?(value, title)
          end

          ##
          # The one owner of the item-wide rule: a label every item of a feed carries says nothing about any
          # one of them.
          #
          # @param category_lists [Array<Array<String>>] one category list per item
          # @return [Array<Array<String>>] the lists without values present in all of them; unchanged for fewer
          #   than {MIN_ITEMS_FOR_SHARED} lists
          def drop_shared(category_lists)
            return category_lists if category_lists.size < MIN_ITEMS_FOR_SHARED

            shared = category_lists.map { |list| list.to_set(&:downcase) }.reduce(:&)
            category_lists.map { |list| list.reject { |value| shared.include?(value.downcase) } }
          end

          ##
          # @param name [String]
          # @return [Boolean]
          def attr_name_match?(name)
            TERM_SET.include?(normalize_attr_name(name))
          end

          ##
          # @param class_names [Array<String>] individual class tokens
          # @return [Boolean]
          def class_match?(class_names)
            class_names.any? { |token| class_token_match?(token) }
          end

          private

          # The value, or one of its separator-set pieces ("Topic // 26.11.2026"), is a date by the one date-shape owner ({Description.date_shaped?}).
          def dated?(value)
            Description.date_shaped?(value) || value.split(PIECE_SEPARATOR).any? { |piece| Description.date_shaped?(piece) }
          end

          def title_prefix?(value, title)
            prefix, rest = title.to_s.split(':', 2)
            !rest.nil? && prefix.strip.casecmp?(value)
          end

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
