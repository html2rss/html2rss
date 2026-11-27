# frozen_string_literal: true

module Html2rss
  class AutoSource
    module EntryResolution
      Options = Data.define(:enabled, :max_probes, :scope)

      ##
      # Typed +auto_source.entry_resolution+ options (one expansion from config Hash).
      class Options
        ##
        # @param auto_source [Hash, nil] validated +auto_source+ config
        # @return [Options]
        def self.from_auto_source(auto_source)
          raw = DEFAULT_CONFIG.merge(auto_source&.dig(:entry_resolution) || {})
          new(enabled: raw.fetch(:enabled), max_probes: raw.fetch(:max_probes), scope: Scope[raw.fetch(:scope)])
        end

        ##
        # @return [Boolean]
        def enabled? = enabled

        ##
        # One slot per probe when enabled; the winner's probe response is extracted without another GET.
        #
        # @return [Integer]
        def request_slots = enabled? ? max_probes : 0
      end
    end
  end
end
