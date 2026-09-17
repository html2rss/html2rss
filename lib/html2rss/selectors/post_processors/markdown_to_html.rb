# frozen_string_literal: true

require 'kramdown'

module Html2rss
  class Selectors
    module PostProcessors
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
        # Expected Ruby class for the extracted value before this post-processor runs.
        VALUE_TYPE = String

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Convert Markdown to HTML (Kramdown) and sanitize the result. ' \
                      'Often chained after `template`.'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'markdown_to_html' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :markdown_to_html, klass: self)

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
end
