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
        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Normalize a URL string; resolve relative URLs against the channel URL.'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'parse_uri' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :parse_uri, klass: self)

        # @param value [String] extracted selector value
        # @param _context [Selectors::Context] post-processor context
        # @return [void]
        def self.validate_args!(value, _context)
          raise ArgumentError, 'The `value` option is missing or empty.' if value.to_s.empty?
        end

        ##
        # @return [String]
        def get
          config_url = context.dig(:config, :channel, :url)

          Url.from_relative(value, config_url).to_s
        end
      end
    end
  end
end
