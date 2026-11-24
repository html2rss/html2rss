# frozen_string_literal: true

module Html2rss
  class Config
    # One auto-source request (URL plus optional hints) from the shortcut APIs, CLI and MCP.
    AutoSourceRequest = Data.define(
      :url, :items_selector, :request_controls, :limit, :keep_different_domain, :keep_sponsored, :local_file_path
    )

    ##
    # Owns the mapping from shortcut inputs to a top-level auto-source feed config.
    class AutoSourceRequest
      # Optional members and their defaults.
      DEFAULTS = {
        items_selector: nil, request_controls: nil, limit: nil,
        keep_different_domain: nil, keep_sponsored: nil, local_file_path: nil
      }.freeze
      private_constant :DEFAULTS

      ##
      # Builds a request whose controls come from the shortcut request keywords.
      #
      # @param url [String] source page URL
      # @param strategy [Symbol, nil] request strategy
      # @param options [Hash{Symbol => Object}] request budgets and optional members
      # @return [AutoSourceRequest]
      def self.from_shortcut(url, strategy:, **options)
        controls = RequestControls.from_shortcut(strategy:, **options.slice(*RequestControls::REQUEST_KEYS))
        new(url:, request_controls: controls, **options.except(*RequestControls::REQUEST_KEYS))
      end

      ##
      # @param url [String] source page URL
      # @param optional [Hash{Symbol => Object}] optional members, see {DEFAULTS}
      def initialize(url:, **optional)
        super(url:, **DEFAULTS, **optional)
      end

      ##
      # @return [Hash{Symbol => Object}] feed config hash ready for {Config.from_hash}
      def to_config
        config = { channel: Config.default_config[:channel].merge(url:), auto_source: }
        (request_controls || RequestControls.new).apply_to(config)
        config[:selectors] = { items: { selector: items_selector, enhance: true } } if items_selector
        config[:request] = (config[:request] || {}).merge(local_file_path:) if local_file_path
        config
      end

      private

      def auto_source
        base = AutoSource::DEFAULT_CONFIG
        base = base.merge(limit: Option.integer(:limit, limit, min: 1)) unless limit.nil?
        cleanup = { keep_different_domain:, keep_sponsored: }.compact
        cleanup.empty? ? base : base.merge(cleanup: base[:cleanup].merge(cleanup))
      end
    end
  end
end
