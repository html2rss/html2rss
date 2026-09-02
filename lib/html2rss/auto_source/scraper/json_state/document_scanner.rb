# frozen_string_literal: true

require 'json'

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Scans DOM nodes for JSON payloads containing article data.
        module DocumentScanner # rubocop:disable Metrics/ModuleLength
          # Regex patterns for known global JavaScript state assignments.
          GLOBAL_ASSIGNMENT_PATTERNS = [
            /(?:window|self|globalThis)\.__NEXT_DATA__\s*=\s*/m,
            /(?:window|self|globalThis)\.__NUXT__\s*=\s*/m,
            /(?:window|self|globalThis)\.STATE\s*=\s*/m,
            /(?:window|self|globalThis)\.__REDUX_STATE__\s*=\s*/m,
            /(?:window|self|globalThis)\.__PRELOADED_STATE__\s*=\s*/m,
            /(?:window|self|globalThis)\.__APOLLO_STATE__\s*=\s*/m,
            /(?:window|self|globalThis)\.__remixContext\s*=\s*/m,
            /(?:window|self|globalThis)\.__sveltekit_data\s*=\s*/m,
            /(?:window|self|globalThis)\.GATSBY_STATE\s*=\s*/m,
            /(?:window|self|globalThis)\.__ember_meta\s*=\s*/m,
            /(?:window|self|globalThis)\.angular\s*=\s*/m
          ].freeze

          # Combined regex for faster matching of global assignments.
          GLOBAL_ASSIGNMENT_REGEXP = Regexp.union(GLOBAL_ASSIGNMENT_PATTERNS).freeze

          module_function

          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @return [Array<Hash, Array>] parsed JSON documents discovered in scripts
          def json_documents(parsed_body)
            # Use identity-based cache to avoid double-parsing of the same document.
            # WeakMap allows the Nokogiri Document (key) to be garbage collected.
            # rubocop:disable ThreadSafety/ClassInstanceVariable
            (@cache ||= ObjectSpace::WeakMap.new)[parsed_body] ||=
              script_documents(parsed_body) + assignment_documents(parsed_body)
            # rubocop:enable ThreadSafety/ClassInstanceVariable
          end

          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @return [Array<Hash, Array>] JSON documents extracted from JSON script tags
          def script_documents(parsed_body)
            ::Html2rss::Html::Probe.scripts(parsed_body, ::Html2rss::Html::Probe::APPLICATION_JSON)
                                   .filter_map { parse_json(_1.text) }
          end

          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @return [Array<Hash, Array>] JSON documents extracted from global assignments
          def assignment_documents(parsed_body)
            parsed_body.css('script').filter_map { parse_assignment(_1.text) }
          end

          # @param text [String] script text that may contain a global assignment
          # @return [Hash, Array, nil] parsed assignment payload when available
          def parse_assignment(text)
            payload = assignment_payload(text)
            parse_json(payload) if payload
          end

          # @param text [String] script text to inspect for known assignment patterns
          # @return [String, nil] extracted JSON-like assignment payload
          def assignment_payload(text)
            trimmed = text.to_s.strip
            return if trimmed.empty?
            return unless trimmed.match?(GLOBAL_ASSIGNMENT_REGEXP)

            payload = trimmed.sub(GLOBAL_ASSIGNMENT_REGEXP, '')
            extract_assignment_payload(payload)
          end

          # @param text [String] text potentially containing JSON-like payloads
          # @return [String, nil] normalized assignment payload
          def extract_assignment_payload(text)
            extract_json_block(text) || text
          end

          # @param text [String] text potentially containing JSON blocks
          # @return [String, nil] extracted JSON block spanning balanced brackets
          def extract_json_block(text)
            start_index = text.index(/[\[{]/)
            return unless start_index

            stop_index = scan_for_json_end(text, start_index)
            text[start_index..stop_index] if stop_index
          end

          # @param text [String] text starting with a JSON object/array opening token
          # @param start_index [Integer] index where JSON-like content starts
          # @return [Integer, nil] index where the balanced JSON payload ends
          def scan_for_json_end(text, start_index) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
            stack = []
            in_string = false
            escape = false

            i = start_index
            len = text.length
            while i < len
              char = text[i]

              if in_string
                if escape
                  escape = false
                elsif char == '\\'
                  escape = true
                elsif char == '"'
                  in_string = false
                end
              else
                case char
                when '"' then in_string = true
                when '{' then stack << '}'
                when '[' then stack << ']'
                when '}', ']'
                  expected = stack.pop
                  return i if expected == char && stack.empty?
                end
              end
              i += 1
            end

            nil
          end

          # @param payload [String, nil] JSON payload to parse
          # @return [Hash, Array, nil] parsed payload or nil when parsing fails
          def parse_json(payload)
            return unless payload

            JSON.parse(payload, symbolize_names: true)
          rescue JSON::ParserError => error
            parse_js_object(payload, error)
          end

          # @param payload [String] JavaScript object-literal payload
          # @param _original_error [JSON::ParserError] original JSON parse error
          # @return [Hash, Array, nil] parsed payload after JavaScript coercion
          def parse_js_object(payload, _original_error)
            coerced = coerce_javascript_object(payload)
            return unless coerced

            # Some sites emit JavaScript object literals (unquoted keys, trailing commas).
            # Coerce those payloads into valid JSON so we keep the same parsing pipeline.
            JSON.parse(coerced, symbolize_names: true)
          rescue JSON::ParserError => error
            Html2rss::Log.debug("JsonState: failed to parse coerced JavaScript object (#{error.message})")
            nil
          end

          # @param payload [String] JavaScript object-literal payload
          # @return [String] JSON-compatible payload string
          def coerce_javascript_object(payload)
            string = payload.dup

            # KISS approach: mutate common JS literal quirks instead of a full parser.
            strip_trailing_commas(quote_unquoted_keys(string))
          end

          # @param jsonish [String] JSON-like string with potentially unquoted keys
          # @return [String] payload with unquoted object keys quoted
          def quote_unquoted_keys(jsonish)
            jsonish.gsub(/(?<prefix>\A\s*|[{,\[]\s*)(?<key>[A-Za-z_]\w*)(?<suffix>\s*:)/) do
              captures = Regexp.last_match.named_captures(symbolize_names: true)
              "#{captures[:prefix]}\"#{captures[:key]}\"#{captures[:suffix]}"
            end
          end

          # @param jsonish [String] JSON-like string with potential trailing commas
          # @return [String] payload without trailing commas before closing tokens
          def strip_trailing_commas(jsonish)
            jsonish.gsub(/,(\s*[\]}])/, '\1')
          end
        end
      end
    end
  end
end
