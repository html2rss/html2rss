# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic datetime aggregation for article published_at.
      module Date
        class << self
          ##
          # @param datetime_strings [Array<String, nil>] raw datetime attribute values
          # @return [DateTime, nil] earliest successfully parsed instant
          def earliest(datetime_strings)
            times = Array(datetime_strings).filter_map do |value|
              DateTime.parse(value.to_s)
            rescue ArgumentError, TypeError
              nil
            end
            times.min
          end
        end
      end
    end
  end
end
