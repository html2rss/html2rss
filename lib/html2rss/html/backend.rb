# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Selects the HTML parser adapter used by {Document}.
    #
    # Override with +HTML2RSS_HTML_BACKEND=nokogiri|nokolexbor|rust+ (default: nokogiri).
    module Backend
      # Env var selecting the active HTML parser adapter.
      ENV_KEY = 'HTML2RSS_HTML_BACKEND'

      # Known adapter names (string form matches env values).
      NAMES = %w[nokogiri nokolexbor rust].freeze

      class << self
        ##
        # @return [Module] active backend (default {Nokogiri})
        def current
          # rubocop:disable ThreadSafety/ClassInstanceVariable -- process-wide experiment switch
          @current ||= resolve(ENV.fetch(ENV_KEY, 'nokogiri'))
          # rubocop:enable ThreadSafety/ClassInstanceVariable
        end

        ##
        # @param name [String, Symbol] backend name
        # @return [Module]
        def use(name)
          # rubocop:disable ThreadSafety/ClassInstanceVariable -- process-wide experiment switch
          @current = resolve(name)
          # rubocop:enable ThreadSafety/ClassInstanceVariable
        end

        ##
        # Clears the memoized backend so the next {.current} re-reads the env.
        #
        # @return [void]
        def reset!
          # rubocop:disable ThreadSafety/ClassInstanceVariable -- process-wide experiment switch
          @current = nil
          # rubocop:enable ThreadSafety/ClassInstanceVariable
        end

        ##
        # @param name [String, Symbol]
        # @return [Module]
        # @raise [ArgumentError] when name is unknown
        def resolve(name)
          case name.to_s.downcase
          when 'nokogiri' then Nokogiri
          when 'nokolexbor' then Nokolexbor
          when 'rust' then Rust
          else
            raise ArgumentError, "Unknown HTML backend #{name.inspect} (expected #{NAMES.join('|')})"
          end
        end
      end
    end
  end
end
