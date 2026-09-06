# frozen_string_literal: true

module Html2rss
  ##
  # Requests website URLs to retrieve their HTML for further processing.
  # Provides concrete transport strategies (e.g. HttpxStrategy, BotasaurusStrategy).
  #
  # Feed-level +:auto+ is not registered here — {FeedPipeline::StrategyPlan} resolves
  # it to a concrete strategy (or {FeedPipeline::AutoFallback} chain) before execute.
  class RequestService
    # Raised when an unknown request strategy is requested.
    class UnknownStrategy < Html2rss::Error; end
    # Raised when a URL cannot be parsed or validated.
    class InvalidUrl < Html2rss::Error; end
    # Raised when a URL uses an unsupported scheme.
    class UnsupportedUrlScheme < Html2rss::Error; end
    # Raised when a response type cannot be parsed.
    class UnsupportedResponseContentType < Html2rss::Error; end
    # Raised when HTTP request slot limits are exceeded.
    class RequestBudgetExceeded < Html2rss::Error; end
    # Raised when policy denies private-network access.
    class PrivateNetworkDenied < Html2rss::Error; end
    # Raised when cross-origin follow-up requests are denied.
    class CrossOriginFollowUpDenied < Html2rss::Error; end
    # Raised when a response exceeds configured size limits.
    class ResponseTooLarge < Html2rss::Error; end
    # Raised when HTTP redirect limits are exceeded.
    class RedirectLimitReached < Html2rss::Error; end
    # Raised when blocked content surfaces are detected.
    class BlockedSurfaceDetected < Html2rss::Error; end

    # Raised when a request times out.
    class RequestTimedOut < Html2rss::Error
      ##
      # @param message [String, nil] timeout failure summary
      # @param timeout_phase [String, nil] scrape-api stage when known (+queue+/+boot+/+work+)
      def initialize(message = nil, timeout_phase: nil)
        @timeout_phase = timeout_phase
        super(message)
      end

      # @return [String, nil] scrape-api timeout stage, or nil for transport/budget timeouts
      attr_reader :timeout_phase
    end

    # Raised when Botasaurus configuration is missing or invalid.
    class BotasaurusConfigurationError < Html2rss::Error
      # Short empty-feed guidance owned once (composed by {Html2rss::NoFeedItemsExtracted}).
      EMPTY_FEED_HINT = 'Configure BOTASAURUS_SCRAPER_URL to enable the Botasaurus request strategy.'
    end

    # Raised when the Botasaurus service cannot be reached (network / DNS / SSL).
    class BotasaurusConnectionFailed < Html2rss::Error; end
    # Raised when Botasaurus responds but the scrape fails (upstream error, bad payload).
    class BotasaurusServiceError < Html2rss::Error; end

    # Map of supported strategy names to their implementation classes.
    # @return [Hash{Symbol => Class<Strategy>}]
    STRATEGIES = {
      default: HttpxStrategy,
      httpx: HttpxStrategy,
      faraday: HttpxStrategy,
      botasaurus: BotasaurusStrategy,
      local_file: LocalFileStrategy
    }.freeze

    # Canonical default strategy symbol.
    # @return [Symbol]
    DEFAULT_STRATEGY_NAME = :default

    class << self
      # @return [Symbol] the default strategy name
      def default_strategy_name = DEFAULT_STRATEGY_NAME

      # @return [Array<String>] the names of the registered strategies
      def strategy_names = STRATEGIES.keys.map(&:to_s)

      ##
      # Checks if a strategy is registered.
      # @param name [Symbol, String] the name of the strategy
      # @return [Boolean] true if the strategy is registered, false otherwise.
      def strategy_registered?(name)
        STRATEGIES.key?(name.to_sym)
      end

      ##
      # Executes the request using the specified strategy.
      # @param ctx [Context] the context for the request.
      # @param strategy [Symbol, String] the strategy to use (defaults to the default strategy).
      # @return [Response] the response from the executed strategy.
      # @raise [UnknownStrategy] if the strategy is not registered.
      def execute(ctx, strategy: default_strategy_name)
        strategy_sym = strategy.to_sym
        strategy_class = STRATEGIES.fetch(strategy_sym) do
          raise UnknownStrategy,
                "The strategy '#{strategy}' is not known. Available strategies: #{strategy_names.join(', ')}"
        end

        warn_migration_strategy(strategy_sym) if strategy_sym == :faraday
        strategy_class.new(ctx).execute
      end

      private

      def warn_migration_strategy(strategy)
        message = "RequestService: strategy ':#{strategy}' is deprecated for migration and will be removed " \
                  "in a future release. Use ':default' instead."
        warn(message, category: :deprecated)
        Log.warn(message)
      end
    end
  end
end
