# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
    ##
    # Returns the URI as String.
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
    class ParseUri
      def initialize(value, _env)
        @value = value
      end

      ##
      # @return [String]
      def get
        URI(Html2rss::Utils.sanitize_url(@value)).to_s
      end
    end
  end
end
