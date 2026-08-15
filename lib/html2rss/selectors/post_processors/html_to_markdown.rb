# frozen_string_literal: true

require 'reverse_markdown'

module Html2rss
  class Selectors
    module PostProcessors
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
      class HtmlToMarkdown < Base
        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Sanitize HTML then convert it to Markdown (via ReverseMarkdown).'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'html_to_markdown' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :html_to_markdown, klass: self)

        # @param value [String] extracted selector value
        # @param context [Selectors::Context] post-processor context
        # @return [void]
        def self.validate_args!(value, context)
          assert_type value, String, :value, context:
        end

        ##
        # @return [String] formatted in Markdown
        def get
          sanitized_value = SanitizeHtml.new(value, context).get

          ReverseMarkdown.convert(sanitized_value)
        end
      end
    end
  end
end
