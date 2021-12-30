# frozen_string_literal: true

require 'reverse_markdown'

module Html2rss
  module AttributePostProcessors
    ##
    # Returns HTML code as Markdown formatted String.
    # Before converting to markdown, the HTML is sanitized with SanitizeHtml.
    # Imagine this HTML structure:
    #
    #     <section>
    #       Lorem <b>ipsum</b> dolor...
    #       <iframe src="https://evil.corp/miner"></iframe>
    #       <script>alert();</script>
    #     </section>
    #
    # YAML usage example:
    #
    #    selectors:
    #      description:
    #        selector: section
    #        extractor: html
    #        post_process:
    #          name: html_to_markdown
    #
    # Would return:
    #    'Lorem **ipsum** dolor'
    class HtmlToMarkdown
      ##
      # @param value [String]
      # @param env [Item::Context]
      def initialize(value, env)
        @value = SanitizeHtml.new(value, env).get
      end

      ##
      # @return [String] formatted in Markdown
      def get
        ReverseMarkdown.convert @value
      end
    end
  end
end
