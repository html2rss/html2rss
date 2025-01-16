# frozen_string_literal: true

require 'singleton'
require 'forwardable'

module Html2rss
  ##
  # Requests website URLs to retrieve their HTML for further processing.
  # Provides strategies, i.e. to integrate Browserless.io.
  class RequestService
    include Singleton

    class UnknownStrategy < Html2rss::Error; end
    class InvalidUrl < Html2rss::Error; end
    class UnsupportedUrlScheme < Html2rss::Error; end
    class UnsupportedResponseContentType < Html2rss::Error; end

    class << self
      extend Forwardable

      %i[default_strategy_name
         default_strategy_name=
         strategy_names
         register_strategy
         unregister_strategy
         strategy_registered?
         execute].each do |method|
        def_delegator :instance, method
      end
    end

    def initialize
      @strategies = {
        faraday: FaradayStrategy,
        browserless: BrowserlessStrategy
      }
      @default_strategy_name = :faraday
    end

    # @return [Symbol] the default strategy name
    attr_reader :default_strategy_name

    ##
    # Sets the default strategy.
    # @param strategy [Symbol] the name of the strategy
    # @raise [UnknownStrategy] if the strategy is not registered
    def default_strategy_name=(strategy)
      raise UnknownStrategy unless strategy_registered?(strategy)

      @default_strategy_name = strategy.to_sym
    end

    # @return [Array<String>] the names of the registered strategies
    def strategy_names = @strategies.keys.map(&:to_s)

    ##
    # Registers a new strategy.
    # @param name [Symbol] the name of the strategy
    # @param strategy_class [Class] the class of the strategy
    def register_strategy(name, strategy_class)
      raise ArgumentError, 'Strategy class must be a Class' unless strategy_class.is_a?(Class)

      @strategies[name.to_sym] = strategy_class
    end

    ##
    # Checks if a strategy is registered.
    # @param name [Symbol] the name of the strategy
    # @return [Boolean] true if the strategy is registered, false otherwise
    def strategy_registered?(name)
      @strategies.key?(name.to_sym)
    end

    ##
    # Unregisters a strategy.
    # @param name [Symbol] the name of the strategy
    # @return [Boolean] true if the strategy was unregistered, false otherwise
    def unregister_strategy(name)
      raise ArgumentError, 'Cannot unregister the default strategy' if name.to_sym == @default_strategy_name

      !!@strategies.delete(name.to_sym)
    end

    ##
    # Executes the request.
    # @param ctx [Context] the context for the request
    # @param strategy [Symbol] the strategy to use
    # @return [Response] the response from the strategy
    # @raise [UnknownStrategy] if the strategy is not known
    def execute(ctx, strategy: default_strategy_name)
      strategy_class = @strategies.fetch(strategy) do
        raise UnknownStrategy,
              "The strategy '#{strategy}' is not known. Available strategies are: #{strategy_names.join(', ')}"
      end
      strategy_class.new(ctx).execute
    end
  end
end
