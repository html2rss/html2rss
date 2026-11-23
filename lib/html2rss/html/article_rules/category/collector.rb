# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      module Category
        ##
        # Accumulates unique category values for one article, keeping insertion order.
        class Collector
          ##
          # @param vocabulary [Vocabulary::Scope] the page language's scope
          # @param title [String, nil] article title used to reject title-echo values
          def initialize(vocabulary:, title: nil)
            @vocabulary = vocabulary
            @title = title
            @values = Set.new
          end

          ##
          # Adds one stripped category value unless it is blank or rejected as chrome.
          #
          # @param text [String, nil]
          # @return [void]
          def add(text)
            value = text.to_s.strip
            return if value.empty?
            return unless Description.keep?(value, vocabulary: @vocabulary, title: @title, type_chips: false)

            @values.add(value)
          end

          ##
          # Adds each non-blank line of newline-delimited text as a separate category value.
          #
          # @param text [String, nil]
          # @return [void]
          def add_split(text)
            return unless text

            text.split(/\n+/).each { |line| add(line) }
          end

          ##
          # @return [Array<String>] collected values in insertion order
          def to_a
            @values.to_a
          end
        end
      end
    end
  end
end
