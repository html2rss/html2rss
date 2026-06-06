# frozen_string_literal: true

module Html2rss
  ##
  # Global configuration defaults for the Html2rss gem.
  class Configuration
    # The valid symbol log levels.
    VALID_LOG_LEVELS = %i[debug info warn error fatal unknown].freeze

    # @return [Object] the logger
    attr_reader :logger

    # @return [Proc, nil] the logger formatter
    attr_reader :logger_formatter

    # @return [Symbol, Integer] the current log level
    attr_reader :log_level

    # @return [Hash, Proc, nil] the globally configured headers
    attr_reader :headers

    # @return [Symbol, nil] the default strategy name
    attr_reader :default_strategy

    # @return [Integer, nil] the minimum TTL in minutes
    attr_reader :min_ttl

    # @return [Array<Hash>] the globally configured stylesheets
    attr_reader :stylesheets

    ##
    # Initializes a new Configuration instance with defaults.
    def initialize
      @logger_formatter = proc do |severity, datetime, _progname, msg|
        "#{datetime} [#{severity}] #{msg}\n"
      end
      @logger = Logger.new($stdout)
      @logger.formatter = @logger_formatter
      self.log_level = ENV.fetch('LOG_LEVEL', :warn)
      @headers = nil
      @default_strategy = nil
      @min_ttl = nil
      @stylesheets = [].freeze
    end

    ##
    # Sets the logger.
    #
    # @param logger [Object]
    # @return [Object] the logger
    def logger=(logger)
      @logger = logger
      @logger.level = @log_level if @logger.respond_to?(:level=)
      @logger.formatter = @logger_formatter if @logger_formatter && @logger.respond_to?(:formatter=)
    end

    ##
    # Sets the log level.
    #
    # @param level [Symbol, String, Integer] the new log level
    # @return [Integer] the normalized log level
    # @raise [ArgumentError] if the log level is invalid
    def log_level=(level)
      @log_level = normalize_log_level(level)
      @logger.level = @log_level if @logger.respond_to?(:level=)
    end

    ##
    # Sets the logger formatter.
    #
    # @param formatter [Proc, #call, nil] the new logger formatter
    # @return [Proc, #call, nil] the new logger formatter
    # @raise [ArgumentError] if formatter does not respond to #call
    def logger_formatter=(formatter)
      raise ArgumentError, 'formatter must respond to #call or be nil' if formatter && !formatter.respond_to?(:call)

      @logger_formatter = formatter
      @logger.formatter = @logger_formatter if @logger.respond_to?(:formatter=)
    end

    ##
    # Sets the global request headers.
    #
    # @param headers [Hash, Proc, #call, nil] the HTTP request headers to globally apply
    # @return [Hash, Proc, #call, nil] the assigned headers
    # @raise [ArgumentError] if headers is not a Hash or callable
    def headers=(headers)
      if headers && !headers.is_a?(Hash) && !headers.respond_to?(:call)
        raise ArgumentError, 'headers must be a Hash or respond to #call'
      end

      @headers = headers.is_a?(Hash) ? headers.dup.freeze : headers
    end

    ##
    # Sets the default strategy.
    #
    # @param strategy [Symbol, String, nil] the strategy name
    # @return [Symbol, nil] the normalized strategy name
    # @raise [ArgumentError] if the strategy is not registered
    def default_strategy=(strategy)
      if strategy.nil?
        @default_strategy = nil
      else
        unless strategy.is_a?(Symbol) || strategy.is_a?(String)
          raise ArgumentError, 'strategy must be a Symbol or String'
        end

        normalized = strategy.to_sym
        raise ArgumentError, "unknown strategy: #{strategy}" unless RequestService.strategy_registered?(normalized)

        @default_strategy = normalized
      end
    end

    ##
    # Sets the minimum TTL in minutes.
    #
    # @param ttl [Integer, String, nil] the minimum TTL
    # @return [Integer, nil] the normalized minimum TTL
    # @raise [ArgumentError] if ttl is not a positive integer
    def min_ttl=(ttl)
      if ttl.nil?
        @min_ttl = nil
      else
        val = Integer(ttl)
        raise ArgumentError unless val.positive?

        @min_ttl = val
      end
    rescue ArgumentError, TypeError
      raise ArgumentError, "min_ttl must be a positive integer, got #{ttl.inspect}"
    end

    ##
    # Sets the global stylesheets.
    #
    # @param stylesheets [Array<Hash>] the XML stylesheet processing instructions to include in the generated feed
    # @return [Array<Hash>] the assigned stylesheets
    # @raise [ArgumentError] if stylesheets is not an Array of hashes
    def stylesheets=(stylesheets)
      raise ArgumentError, 'stylesheets must be an Array' unless stylesheets.is_a?(Array)
      raise ArgumentError, 'stylesheets must be an Array of Hashes' unless stylesheets.all?(Hash)

      @stylesheets = stylesheets.map { |h| h.dup.freeze }.freeze
    end

    protected

    ##
    # Copy constructor for duplicating configuration.
    #
    # @param other [Html2rss::Configuration] the original configuration
    # @return [void]
    def initialize_copy(other)
      super
      @headers = @headers.dup if @headers.is_a?(Hash)
      @stylesheets = @stylesheets.map(&:dup) if @stylesheets.is_a?(Array)
    end

    private

    def normalize_log_level(level)
      if level.is_a?(Integer)
        raise ArgumentError, "invalid log level: #{level}" unless level.between?(0, 5)

        level
      else
        sym = level.to_s.downcase.to_sym
        raise ArgumentError, "invalid log level: #{level}" unless VALID_LOG_LEVELS.include?(sym)

        Logger.const_get(sym.upcase)
      end
    end
  end
end
