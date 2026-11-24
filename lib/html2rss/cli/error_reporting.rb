# frozen_string_literal: true

module Html2rss
  class CLI < Thor
    ##
    # Single owner of CLI error reporting: every command runs through
    # +invoke_command+, so a gem error prints one line (exit 1) instead of a
    # stack trace. A ContractError is a bug and keeps its trace.
    module ErrorReporting
      # @return [Object] the command result
      # @raise [Thor::Error] for any non-contract Html2rss::Error
      def invoke_command(...)
        super
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error => error
        raise Thor::Error, gem_error_message(error)
      end

      private

      # @param error [Html2rss::Error]
      # @return [String] one-line message, with a retry hint for request limits
      def gem_error_message(error)
        case error
        when RequestService::RedirectLimitReached
          "#{error}. already retried the last redirect hop once; " \
          'retry with higher --max-redirects or use the final URL directly.'
        when RequestService::RequestBudgetExceeded
          "#{error}. retry with higher --max-requests or increase request.max_requests in config."
        else error.message
        end
      end
    end
  end
end
