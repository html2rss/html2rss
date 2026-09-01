# frozen_string_literal: true

module Html2rss
  class CLI
    ##
    # Display-only probe facts for inspect and recon text cards.
    ProbeView = Data.define(
      :requested,
      :final,
      :status,
      :surface,
      :articles_count,
      :verdict,
      :native_feed,
      :alternate_feeds,
      :notes,
      :strategy
    ) do
      class << self
        ##
        # @param data [Hash] inspect wire payload
        # @return [ProbeView]
        def from_wire(data) # rubocop:disable Metrics/MethodLength
          new(
            requested: wire_val(data, :requested_url),
            final: wire_val(data, :final_url),
            status: wire_val(data, :status),
            surface: wire_val(data, :surface_category),
            articles_count: wire_val(data, :articles_count),
            verdict: nil,
            native_feed: nil,
            alternate_feeds: wire_val(data, :alternate_feeds) || [],
            notes: [],
            strategy: wire_val(data, :strategy)
          )
        end

        ##
        # @param result [Html2rss::Recon::Result]
        # @return [ProbeView]
        def from_recon(result) # rubocop:disable Metrics/MethodLength
          new(
            requested: result.requested_url.to_s,
            final: result.final_url.to_s,
            status: result.status,
            surface: result.surface_category,
            articles_count: result.articles_count,
            verdict: result.verdict,
            native_feed: result.native_feed&.to_s,
            alternate_feeds: [],
            notes: result.notes,
            strategy: nil
          )
        end

        ##
        # @param data [Hash]
        # @param key [Symbol]
        # @return [Object, nil]
        def wire_val(data, key)
          data[key] || data[key.to_s]
        end
      end
    end
  end
end
