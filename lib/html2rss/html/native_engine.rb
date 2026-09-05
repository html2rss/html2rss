# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Entry for the optional Rust +html2rss_parser+ native extension.
    #
    # Compile with +bundle exec rake compile+. The gem does not declare
    # +spec.extensions+ in this experiment wave — missing build yields {LoadError}.
    module NativeEngine
      # Raised when the native parser rejects markup (Magnus maps parse failures here).
      class SyntaxError < StandardError; end

      class << self
        ##
        # Require the compiled extension.
        #
        # @return [void]
        # @raise [LoadError] when the extension is not compiled
        def load!
          return if @loaded

          require 'html2rss/html2rss_parser'
          @loaded = true
        rescue LoadError => e
          raise LoadError,
                'html2rss_parser native extension is not compiled. ' \
                "Run `bundle exec rake compile` (requires a Rust toolchain). (#{e.message})"
        end

        ##
        # @return [Boolean] true when the extension is already loaded or loadable
        def available?
          load!
          true
        rescue LoadError
          false
        end
      end

      # After {NativeEngine.load!}, the extension also defines:
      # - {.to_sst} +html+ → {Html2rss::SST::Document}
      # - {.stripped_tags} / {.max_nodes} / {.semantic_degrade_tags} for constants sync
    end
  end
end
