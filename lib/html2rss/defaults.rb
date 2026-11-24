# frozen_string_literal: true

module Html2rss
  ##
  # Global defaults for the Html2rss gem.
  class Defaults
    # Named Logger severities accepted by {#log_level=}.
    LOG_LEVELS = {
      debug: Logger::DEBUG,
      info: Logger::INFO,
      warn: Logger::WARN,
      error: Logger::ERROR,
      fatal: Logger::FATAL,
      unknown: Logger::UNKNOWN
    }.freeze

    # @return [Logger] the logger
    attr_reader :logger

    # @return [Proc, Logger::Formatter, nil] the logger formatter
    attr_reader :logger_formatter

    # @return [Symbol, Integer] the current log level
    attr_reader :log_level

    # @return [Hash, Proc, nil] the globally configured headers
    attr_reader :headers

    # @return [Array<Hash>] the globally configured stylesheets
    attr_reader :stylesheets

    ##
    # Initializes a new Defaults instance.
    def initialize
      @logger_formatter = proc do |severity, datetime, _progname, msg|
        "#{datetime} [#{severity}] #{msg}\n"
      end
      @logger = Logger.new($stdout)
      @logger.formatter = @logger_formatter
      self.log_level = ENV.fetch('LOG_LEVEL', :warn)
      @headers = nil
      @stylesheets = [].freeze
    end

    ##
    # Sets the logger.
    #
    # @param logger [Logger]
    # @return [Logger] the logger
    # @raise [InvalidOption] if logger is not a Logger
    def logger=(logger)
      raise InvalidOption, 'logger must be a Logger' unless logger.is_a?(Logger)

      @logger = logger
      @logger.level = @log_level
      @logger.formatter = @logger_formatter if @logger_formatter
    end

    ##
    # Sets the log level.
    #
    # @param level [Symbol, String, Integer] the new log level
    # @return [Integer] the normalized log level
    # @raise [InvalidOption] if the log level is invalid
    def log_level=(level)
      @log_level = normalize_log_level(level)
      @logger.level = @log_level
    end

    ##
    # Sets the logger formatter.
    #
    # @param formatter [Proc, Logger::Formatter, nil] the new logger formatter
    # @return [Proc, Logger::Formatter, nil] the new logger formatter
    # @raise [InvalidOption] if formatter is not a Proc, Logger::Formatter, or nil
    def logger_formatter=(formatter)
      @logger_formatter = case formatter
                          when nil, Proc, Logger::Formatter
                            formatter
                          else
                            raise InvalidOption, 'formatter must be a Proc, Logger::Formatter, or nil'
                          end
      @logger.formatter = @logger_formatter
    end

    ##
    # Sets the global request headers.
    #
    # @param headers [Hash, Proc, nil] the HTTP request headers to globally apply
    # @return [Hash, Proc, nil] the assigned headers
    # @raise [InvalidOption] if headers is not a Hash, Proc, or nil
    def headers=(headers)
      @headers = case headers
                 when nil then nil
                 when Hash then headers.dup.freeze
                 when Proc then headers
                 else
                   raise InvalidOption, 'headers must be a Hash or Proc'
                 end
    end

    ##
    # Sets the global stylesheets.
    #
    # @param stylesheets [Array<Hash>] the XML stylesheet processing instructions to include in the generated feed
    # @return [Array<Hash>] the assigned stylesheets
    # @raise [InvalidOption] if stylesheets is not an Array of hashes
    def stylesheets=(stylesheets)
      raise InvalidOption, 'stylesheets must be an Array' unless stylesheets.is_a?(Array)
      raise InvalidOption, 'stylesheets must be an Array of Hashes' unless stylesheets.all?(Hash)

      @stylesheets = stylesheets.map { |h| h.dup.freeze }.freeze
    end

    protected

    ##
    # Copy constructor for duplicating defaults.
    #
    # @param other [Html2rss::Defaults] the original defaults
    # @return [void]
    def initialize_copy(other)
      super
      @headers = other.headers.dup if other.headers.is_a?(Hash)
      @stylesheets = other.stylesheets.map(&:dup)
    end

    private

    def normalize_log_level(level)
      if level.is_a?(Integer)
        raise InvalidOption, "invalid log level: #{level}" unless LOG_LEVELS.value?(level)

        level
      else
        LOG_LEVELS.fetch(level.to_s.downcase.to_sym) { raise InvalidOption, "invalid log level: #{level}" }
      end
    end
  end
end
