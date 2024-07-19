# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
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
    class ParseUri
      ##
      # @param value [String]
      # @param context [Item::Context]
      def initialize(value, context)
        @value = value
        @config_url = context.config.url
      end

      ##
      # @return [String]
      def get
        Html2rss::Utils.build_absolute_url_from_relative(
          Html2rss::Utils.sanitize_url(@value),
          @config_url
        ).to_s
      end
    end
  end
end
