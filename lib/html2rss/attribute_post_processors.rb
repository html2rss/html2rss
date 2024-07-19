# frozen_string_literal: true

module Html2rss
  ##
  # Provides a namespace for attribute post processors.
  module AttributePostProcessors
    ##
    # Error raised when an unknown post processor name is requested.
    class UnknownPostProcessorName < StandardError; end

    ##
    # Maps the post processor name to the class implementing the post processor.
    #
    # The key is the name to use in the feed config.
    NAME_TO_CLASS = {
      gsub: Gsub,
      html_to_markdown: HtmlToMarkdown,
      markdown_to_html: MarkdownToHtml,
      parse_time: ParseTime,
      parse_uri: ParseUri,
      sanitize_html: SanitizeHtml,
      substring: Substring,
      template: Template
    }.freeze

    ##
    # Retrieves the attribute post processor class based on the given name.
    #
    # @param name [Symbol] The name of the post processor.
    # @return [Class] The attribute post processor class.
    # @raise [UnknownPostProcessorName] If the requested name is not found in NAME_TO_CLASS.
    def self.get_processor(name)
      NAME_TO_CLASS[name.to_sym] || raise(UnknownPostProcessorName, "Can't find a post processor named '#{name}'")
    end
  end
end
