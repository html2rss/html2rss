# frozen_string_literal: true

module Html2rss
  ##
  # Requests website URLs to retreive their HTML for further processing.
  # Provides strategies, i.e. to integrate Browserless.io.
  class RequestService
    class UnknownStrategy < Html2rss::Error; end
    class InvalidUrl < Html2rss::Error; end
    class UnsupportedUrlScheme < Html2rss::Error; end

    STRATEGIES = {
      faraday: FaradayStrategy,
      browserless: BrowserlessStrategy
    }.freeze

    DEFAULT_STRATEGY = :faraday

    ##
    # Executes the request.
    # @param ctx [Context] the context for the request
    # @param strategy [Symbol] the strategy to use
    # @return [Response] the response from the strategy
    # @raise [UnknownStrategy] if the strategy is not known
    def self.execute(ctx, strategy: DEFAULT_STRATEGY)
      strategy_class = STRATEGIES.fetch(strategy.to_sym) do
        raise UnknownStrategy,
              "The strategy '#{strategy}' is not known. Available strategies are: #{STRATEGIES.keys.join(', ')}"
      end
      strategy_class.new(ctx).execute
    end
  end
end
