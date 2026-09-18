# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Provides a namespace for selector post processors.
    module PostProcessors
      ##
      # Error raised when an unknown post processor name is requested.
      class UnknownPostProcessorName < Html2rss::Error; end

      ##
      # Error raised when a required option is missing.
      class MissingOption < Html2rss::Error; end

      ##
      # Error raised when an invalid type is provided.
      class InvalidType < Html2rss::Error; end

      ##
      # Maps the post processor name to the class implementing the post processor.
      #
      # The key is the name to use in the feed config.
      NAME_TO_CLASS = {
        gsub: Gsub,
        markdown_to_html: MarkdownToHtml,
        parse_time: ParseTime,
        parse_uri: ParseUri,
        sanitize_html: SanitizeHtml,
        substring: Substring,
        template: Template
      }.freeze

      ##
      # Registry dispatcher: resolves the post-processor strategy for +name+,
      # instantiates it with +(value, context)+, and executes its +#call+.
      #
      # @param name [String, Symbol] post-processor name from selector config
      # @param value [Object] extracted selector value
      # @param context [Selectors::StepEnv] post-processor step context carrying +step_config+
      # @return [Object] transformed selector value
      def self.call(name, value, context)
        klass = NAME_TO_CLASS[name.to_sym] || raise(UnknownPostProcessorName, "Unknown name '#{name}'")
        klass.new(value, context).call
      end
    end
  end
end
