# frozen_string_literal: true

module Html2rss
  ##
  # Requests website URLs to retrieve their HTML for further processing.
  # Provides concrete transport strategies (e.g. HttpxStrategy, BotasaurusStrategy).
  #
  # Feed-level +:auto+ is not registered here — {FeedPipeline::StrategyPlan} resolves
  # it to a concrete strategy (or {FeedPipeline::AutoFallback} chain) before execute.
  class RequestService
    extend ResponseCaching

    # Raised when an unknown request strategy is requested.
    class UnknownStrategy < Html2rss::Error; end

    # Raised when a URL cannot be parsed or validated.
    class InvalidUrl < Html2rss::Error
      # @return [Symbol]
      def kind = :invalid_url
    end

    # Raised when a URL uses an unsupported scheme.
    class UnsupportedUrlScheme < Html2rss::Error
      # @return [String, nil] the https form of a downgraded redirect target, the URL to retry with
      attr_reader :retry_url

      ##
      # @param message [String]
      # @param retry_url [String, Html2rss::Url, nil] https form of the downgraded target
      def initialize(message, retry_url: nil)
        @retry_url = retry_url&.to_s
        super(message)
      end

      # @return [Symbol]
      def kind = :invalid_url

      # @return [Hash{Symbol => Object}] sparse diagnostics including +retry_url+ when known
      def diagnostics = { **super, retry_url: }.compact
    end

    # Raised when the entry response carries a permanent HTTP status (a missing or refused page),
    # so no strategy, extraction or entry resolution can change the outcome.
    class DeterministicHttpStatus < Html2rss::Error
      # Statuses that mean the page is permanently unavailable rather than an anti-bot challenge.
      STATUSES = Set[400, 404, 410, 422, 451].freeze

      ##
      # @param response [Response] the entry response
      # @return [void]
      # @raise [DeterministicHttpStatus] when the response status is in {STATUSES}
      # @note Call {RequestService.check_entry_status!}, which also gates {BlockedSurfaceDetected::STATUSES}.
      def self.check!(response)
        return unless STATUSES.member?(response.status)

        raise new("HTTP #{response.status} for #{response.url}", status: response.status, url: response.url)
      end

      # @return [Integer, nil] the HTTP status of the entry response
      attr_reader :status

      # @return [Html2rss::Url, nil] the entry URL
      attr_reader :url

      ##
      # @param message [String]
      # @param status [Integer, nil]
      # @param url [Html2rss::Url, nil]
      def initialize(message, status: nil, url: nil)
        @status = status
        @url = url
        super(message)
      end

      # @return [Hash{Symbol => Object}] sparse diagnostics including the HTTP +status+
      def diagnostics = { **super, status: }.compact
    end

    # Raised when a response type cannot be parsed.
    class UnsupportedResponseContentType < Html2rss::Error; end

    # Raised when HTTP request slot limits are exceeded.
    class RequestBudgetExceeded < Html2rss::Error
      # @return [Symbol]
      def kind = :budget
    end

    # Raised when policy denies private-network access.
    class PrivateNetworkDenied < Html2rss::Error
      # @return [Symbol]
      def kind = :blocked
    end

    # Raised when cross-origin follow-up requests are denied.
    class CrossOriginFollowUpDenied < Html2rss::Error
      # @return [Symbol]
      def kind = :blocked
    end

    # Raised when a response exceeds configured size limits.
    class ResponseTooLarge < Html2rss::Error
      # @return [Symbol]
      def kind = :budget
    end

    # Raised when HTTP redirect limits are exceeded.
    class RedirectLimitReached < Html2rss::Error
      # @return [Symbol]
      def kind = :budget
    end

    # Raised when blocked content surfaces are detected.
    class BlockedSurfaceDetected < Html2rss::Error
      # Entry statuses that mean the site refused us (auth wall, forbidden, rate limit): the body is never content.
      STATUSES = Set[401, 403, 429].freeze

      # @return [Integer, nil] the HTTP status of the entry response, when the block came from the status
      attr_reader :status

      ##
      # @param message [String]
      # @param status [Integer, nil]
      def initialize(message, status: nil)
        @status = status
        super(message)
      end

      # @return [Symbol]
      def kind = :blocked

      # @return [Hash{Symbol => Object}] sparse diagnostics including the HTTP +status+
      def diagnostics = { **super, status: }.compact
    end

    # Raised when the target connection fails before a response document exists.
    class ConnectionFailed < Html2rss::Error
      # @return [Symbol]
      def kind = :connection
    end

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

      # @return [Symbol]
      def kind = :timeout
    end

    # Raised when Botasaurus configuration is missing or invalid.
    class BotasaurusConfigurationError < Html2rss::Error
      # Short empty-feed guidance owned once (composed by {Html2rss::FeedPipeline.empty_feed_error}).
      EMPTY_FEED_HINT = 'Configure BOTASAURUS_SCRAPER_URL to enable the Botasaurus request strategy.'
    end

    # Raised when the Botasaurus service cannot be reached (network / DNS / SSL).
    class BotasaurusConnectionFailed < Html2rss::Error
      # @return [Symbol]
      def kind = :connection
    end

    # Raised when Botasaurus responds but the scrape fails (upstream error, bad payload).
    class BotasaurusServiceError < Html2rss::Error; end

    # Map of supported strategy names to their implementation classes.
    # @return [Hash{Symbol => Class<Strategy>}]
    STRATEGIES = {
      default: HttpxStrategy,
      httpx: HttpxStrategy,
      faraday: HttpxStrategy,
      botasaurus: BotasaurusStrategy,
      browserless: BotasaurusStrategy,
      local_file: LocalFileStrategy
    }.freeze

    # Deprecated strategy aliases and the preferred replacement name for warnings.
    # @return [Hash{Symbol => Symbol}]
    MIGRATION_REPLACEMENTS = {
      faraday: :default,
      browserless: :botasaurus
    }.freeze

    # Canonical default strategy symbol.
    # @return [Symbol]
    DEFAULT_STRATEGY_NAME = :default

    # Maximum distinct [strategy, host] deprecation warnings tracked per process.
    MAX_DEPRECATION_WARNINGS = 256
    # Mutex guarding process-local deprecation warning deduplication.
    DEPRECATION_MUTEX = Mutex.new
    # Mutex guarding the process-wide cookie store reference.
    COOKIE_STORE_MUTEX = Mutex.new
    private_constant :DEPRECATION_MUTEX, :COOKIE_STORE_MUTEX

    # Default `User-Agent` sent by every transport.
    DEFAULT_USER_AGENT = "html2rss/#{Html2rss::VERSION}".freeze

    class << self
      ##
      # The one gate for "the entry status decides the outcome": a permanent status raises
      # {DeterministicHttpStatus}, a refusal status raises {BlockedSurfaceDetected}. Runs on the entry
      # response before any extraction or entry resolution.
      #
      # @param response [Response] the entry response
      # @return [void]
      # @raise [DeterministicHttpStatus, BlockedSurfaceDetected]
      def check_entry_status!(response)
        DeterministicHttpStatus.check!(response)
        return unless BlockedSurfaceDetected::STATUSES.member?(response.status)

        raise BlockedSurfaceDetected.new("HTTP #{response.status} for #{response.url}", status: response.status)
      end

      # @return [Boolean] whether +BOTASAURUS_SCRAPER_URL+ carries a value in this process
      def botasaurus_configured?
        !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
      end

      # @param store [#fetch, #write, #evict, nil] replacement cookie store (nil restores the in-memory default)
      # @return [void]
      def cookie_store=(store)
        COOKIE_STORE_MUTEX.synchronize { @cookie_store = store }
      end

      # @return [#fetch, #write, #evict] the configured cookie store (in-memory by default)
      def cookie_store
        COOKIE_STORE_MUTEX.synchronize { @cookie_store ||= CookieStore.new }
      end

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
        strategy_sym = resolve_strategy_name(strategy, relation: ctx.relation, host: ctx.url.host)
        strategy_class = STRATEGIES.fetch(strategy_sym) do
          raise UnknownStrategy,
                "The strategy '#{strategy}' is not known. Available strategies: #{strategy_names.join(', ')}"
        end

        fetch_initial_through_cache(ctx, strategy_sym) { strategy_class.new(ctx).execute }
      end

      ##
      # Clears process-local deprecation warning state (used by specs).
      # @return [void]
      def reset_deprecation_warnings!
        DEPRECATION_MUTEX.synchronize { @warned_deprecations = Set.new }
      end

      private

      ##
      # Resolves deprecated migration aliases to their replacement strategy name.
      # @param strategy [Symbol, String] requested strategy name
      # @param relation [Symbol] request relation (+ :initial + or follow-up)
      # @param host [String, nil] request host for structured deprecation telemetry
      # @return [Symbol] canonical strategy name after migration remapping
      def resolve_strategy_name(strategy, relation:, host:)
        strategy_sym = strategy.to_sym
        replacement = MIGRATION_REPLACEMENTS[strategy_sym]
        return strategy_sym unless replacement

        warn_migration_strategy(strategy_sym, replacement, relation:, host:)
        replacement
      end

      ##
      # Emits a structured +strategy_deprecated+ warning once per +(strategy, host)+ per process
      # on initial session requests (+relation == :initial+). Multi-worker servers may emit once per worker.
      # @param strategy [Symbol] deprecated strategy alias
      # @param replacement [Symbol] preferred strategy name
      # @param relation [Symbol] request relation
      # @param host [String, nil] request host
      # @return [void]
      def warn_migration_strategy(strategy, replacement, relation:, host:)
        return unless relation == :initial && claim_deprecation_warning?(strategy, host)

        Log.event(
          :warn, 'strategy_deprecated',
          strategy: strategy.to_s,
          replacement: replacement.to_s,
          host:,
          message: "#{name}: strategy=#{strategy.inspect} is deprecated; using #{replacement.inspect} instead."
        )
      end

      def claim_deprecation_warning?(strategy, host)
        DEPRECATION_MUTEX.synchronize do
          @warned_deprecations ||= Set.new
          @warned_deprecations.clear if @warned_deprecations.size >= MAX_DEPRECATION_WARNINGS
          !@warned_deprecations.add?([strategy, host]).nil?
        end
      end
    end
  end
end
