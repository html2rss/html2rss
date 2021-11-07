# frozen_string_literal: true

module Html2rss
  ##
  # Provides a namespace for attribute post processors.
  module AttributePostProcessors
    ##
    # The Error class to be thrown when an unknown (= absent in NAME_TO_CLASS
    # mapping) post processor is requested.
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
    # @param name [String]
    # @return [Class] the attribute post processor
    def self.get_processor(name)
      NAME_TO_CLASS[name.to_sym] || raise(UnknownPostProcessorName,
                                          "Can't find an post processor named '#{name}' in NAME_TO_CLASS")
    end
  end
end
