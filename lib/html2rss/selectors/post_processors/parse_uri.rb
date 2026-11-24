# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      ##
      # Returns the normalized URL as a String.
      # If the URL is relative, it resolves it against the channel URL.
      #
      # Imagine this HTML structure:
      #
      #    <span>http://why-not-use-a-link.uh </span>
      #
      # YAML usage example:
      #
      #    selectors:
      #      link:
      #        selector: span
      #        extractor: text
      #        post_process:
      #          name: parse_uri
      #
      # Would return:
      #    'http://why-not-use-a-link.uh'
      class ParseUri < Base
        # Expected Ruby class for the extracted value; any type is accepted.
        VALUE_TYPE = nil

        # Config-facing options contract (none).
        OPTIONS = [].freeze

        # JSON Schema description, exported by {SchemaExport}.
        DESCRIPTION = 'Normalize a URL string; resolve relative URLs against the channel URL.'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'parse_uri' }
        ].freeze

        # @param value [String] extracted selector value
        # @param _context [Selectors::StepEnv] post-processor context
        # @return [void]
        def self.validate_args!(value, _context)
          raise MissingOption, 'The `value` option is missing or empty.' if value.to_s.empty?
        end

        ##
        # @return [String, nil] nil when +value+ is blank or unparseable
        def call
          Url.resolve_web(value, context.base_url, web_only: false)&.to_s
        end
      end
    end
  end
end
