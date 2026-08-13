# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic image URL selection (srcset sizing, CSS background urls).
      module Image
        SRCSET_PAIR = /(\S+)\s+(\d+w|\d+h)[\s,]?/
        STYLE_URL = /url\(['"]?(.*?)['"]?\)/

        class << self
          ##
          # @param srcset_strings [Array<String>] raw srcset attribute values
          # @return [String, nil] URL of the largest width/height candidate
          def largest_from_srcsets(srcset_strings)
            by_size = {}
            Array(srcset_strings).each do |srcset|
              srcset.to_s.scan(SRCSET_PAIR) do |url, width|
                next if url.nil? || url.start_with?('data:')

                width_value = width.to_i.zero? ? 0 : width.scan(/\d+/).first.to_i
                by_size[width_value] = url.strip
              end
            end
            by_size[by_size.keys.max]
          end

          ##
          # @param style_strings [Array<String>] CSS style attribute values
          # @return [String, nil] longest non-data background url
          def best_from_styles(style_strings)
            Array(style_strings)
              .filter_map { |style| style.to_s[STYLE_URL, 1] }
              .reject { |src| src.start_with?('data:') }
              .max_by(&:size)
          end
        end
      end
    end
  end
end
