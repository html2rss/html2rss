# frozen_string_literal: true

require 'kramdown'
require_relative 'sanitize_html'

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
    class MarkdownToHtml < Base
      def self.validate_args!(value, context)
        assert_type value, String, :value, context:
      end

      ##
      # Converts Markdown to sanitized HTML.
      #
      # @return [String] Sanitized HTML content
      def get
        html_content = Kramdown::Document.new(value).to_html
        SanitizeHtml.new(html_content, context).get
      end
    end
  end
end
