# frozen_string_literal: true

module Html2rss
  ##
  # Forwards debug/info/warn/error to {Html2rss.logger}.
  module Log
    # Raised by {.event} for a level outside +:debug+, +:info+, +:warn+, +:error+.
    class UnknownLevelError < Html2rss::ContractError; end

    class << self
      ##
      # @return [true]
      def debug(...) = Html2rss.logger.debug(...)

      ##
      # @return [true]
      def info(...) = Html2rss.logger.info(...)

      ##
      # @return [true]
      def warn(...) = Html2rss.logger.warn(...)

      ##
      # @return [true]
      def error(...) = Html2rss.logger.error(...)

      ##
      # Emits one structured log line: JSON with +event_name+ first, then +fields+ in order. The JSON of a
      # +:debug+ event is built only when the logger has debug enabled.
      #
      # @param level [Symbol] one of +:debug+, +:info+, +:warn+, +:error+
      # @param name [String] the event name
      # @param fields [Hash{Symbol => Object}] JSON-serializable payload fields
      # @option fields [Object] :* any field, serialized in the order given
      # @return [true]
      # @raise [UnknownLevelError] when +level+ is not one of the four
      def event(level, name, **fields)
        return true if level == :debug && !Html2rss.logger.debug?

        line = { event_name: name, **fields }.to_json
        case level
        when :debug then debug(line)
        when :info then info(line)
        when :warn then Log.warn(line)
        when :error then error(line)
        else raise UnknownLevelError, "unknown log level: #{level.inspect}"
        end
      end
    end
  end
end
