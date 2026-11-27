# frozen_string_literal: true

module Html2rss
  class Config
    AutoSourceRequest = Data.define(
      :url, :items_selector, :request_controls, :limit, :keep_different_domain, :keep_sponsored, :local_file_path,
      :resolution_scope
    )

    ##
    # One auto-source request (URL plus optional hints) from the shortcut APIs, CLI and MCP.
    # Owns the mapping from shortcut inputs to a top-level auto-source feed config.
    class AutoSourceRequest
      # Optional members and their defaults.
      DEFAULTS = {
        items_selector: nil, request_controls: nil, limit: nil,
        keep_different_domain: nil, keep_sponsored: nil, local_file_path: nil, resolution_scope: nil
      }.freeze
      private_constant :DEFAULTS

      ##
      # Builds a request whose controls come from the shortcut request keywords.
      #
      # @param url [String] source page URL
      # @param strategy [Symbol, nil] request strategy
      # @option options [Integer, nil] :max_redirects redirect limit override
      # @option options [Integer, nil] :max_requests request budget override
      # @option options [Integer, nil] :total_timeout_seconds wall-clock bound for the request chain
      # @option options [Object] :items_selector, :limit, :keep_different_domain, :keep_sponsored, :local_file_path,
      #   :resolution_scope
      #   see {#initialize}
      # @return [AutoSourceRequest]
      # @raise [InvalidOption] when +options+ contains +:url+
      def self.from_shortcut(url, strategy:, **options)
        raise InvalidOption, 'unknown keyword: :url' if options.key?(:url)

        controls = RequestControls.from_shortcut(strategy:, **options.slice(*RequestControls::REQUEST_KEYS))
        new(url:, request_controls: controls, **options.except(*RequestControls::REQUEST_KEYS))
      end

      ##
      # @param url [String] source page URL
      # @option optional [String, nil] :items_selector selector hint for item extraction
      # @option optional [Config::RequestControls, nil] :request_controls explicit request controls to write
      # @option optional [Integer, nil] :limit max articles to keep
      # @option optional [Boolean, nil] :keep_different_domain overrides cleanup.keep_different_domain
      # @option optional [Boolean, nil] :keep_sponsored overrides cleanup.keep_sponsored
      # @option optional [String, nil] :local_file_path local HTML file path
      # @option optional [String, Symbol, nil] :resolution_scope +section+ or +site+, overrides
      #   auto_source.entry_resolution.scope
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

      def resolution_config = AutoSource::DEFAULT_CONFIG[:entry_resolution].merge(scope: resolution_scope.to_s)

      def auto_source
        base = AutoSource::DEFAULT_CONFIG
        base = base.merge(limit: Option.integer(:limit, limit, min: 1)) unless limit.nil?
        base = base.merge(entry_resolution: resolution_config) if resolution_scope
        cleanup = { keep_different_domain:, keep_sponsored: }.compact
        cleanup.empty? ? base : base.merge(cleanup: base[:cleanup].merge(cleanup))
      end
    end
  end
end
