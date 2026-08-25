# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Typed +auto_source.entry_resolution+ options (one expansion from config Hash).
    Options = Data.define(:enabled, :max_probes) do
      ##
      # @param auto_source [Hash, nil]
      # @return [Options]
      def self.from_auto_source(auto_source)
        raw = auto_source.is_a?(Hash) ? auto_source[:entry_resolution] : nil
        raw = {} unless raw.is_a?(Hash)
        new(
          enabled: raw.fetch(:enabled, FeedResolution::DEFAULT_CONFIG[:enabled]) != false,
          max_probes: Integer(raw.fetch(:max_probes, FeedResolution::DEFAULT_CONFIG[:max_probes]))
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
