# frozen_string_literal: true

require 'kramdown'

module Html2rss
  module AttributePostProcessors
    ##
    # Generates HTML from Markdown.
    #
    # It's particularly useful in conjunction with the Template post processor
    # to generate a description from other selectors.
    #
    # YAML usage example:
    #
    #    selectors:
    #      description:
    #        selector: section
    #        post_process:
    #          - name: template
    #            string: |
    #              # %s
    #
    #              Price: %s
    #            methods:
    #              - self
    #              - price
    #          - name: markdown_to_html
    #
    # Would e.g. return:
    #
    #    <h1>Section</h1>
    #
    #    <p>Price: 12.34</p>
    class MarkdownToHtml
      def initialize(value, env)
        @value = value
        @env = env
      end

      ##
      # @return [String] formatted in Markdown
      def get
        SanitizeHtml.new(Kramdown::Document.new(@value).to_html, @env).get
      end
    end
  end
end
