# frozen_string_literal: true

module Html2rss
  module FeedResolution
    Options = Data.define(:enabled, :max_probes)

    ##
    # Typed +auto_source.entry_resolution+ options (one expansion from config Hash).
    class Options
      ##
      # @param auto_source [Hash, nil]
      # @return [Options]
      def self.from_auto_source(auto_source)
        raw = auto_source[:entry_resolution] if auto_source.is_a?(Hash)
        raw = {} unless raw.is_a?(Hash)
        new(
          enabled: raw[:enabled] != false,
          max_probes: Integer(raw.fetch(:max_probes, DEFAULT_CONFIG[:max_probes]))
        )
      end

      ##
      # @return [Boolean]
      def enabled? = enabled

      ##
      # Probe slots plus one Orchestrator retry GET when enabled.
      #
      # @return [Integer]
      def request_slots = enabled? ? max_probes + 1 : 0
    end
  end
end
