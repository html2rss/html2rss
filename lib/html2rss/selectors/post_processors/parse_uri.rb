# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      ##
      # Returns the URI as String.
      # If the URL is relative, it builds an absolute one with the channel's URL as base.
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
