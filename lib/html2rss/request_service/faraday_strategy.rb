# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/gzip'

module Html2rss
  class RequestService
    ##
    # Strategy to use Faraday for the request.
    # @see https://rubygems.org/gems/faraday
    # rubocop:disable Metrics/ClassLength -- terminal redirect retry colocated with Faraday transport
    class FaradayStrategy < Strategy
      ##
      # Restores buffered streamed bytes so response middleware can process them.
      class StreamingBodyMiddleware < Faraday::Middleware
        # Request-context key used to store streamed chunks before middleware completion.
        STREAM_BUFFER_KEY = :html2rss_stream_buffer

        # @param env [Faraday::Env] completed response environment
        # @return [void]
        def on_complete(env)
          buffer = env.request.context&.delete(STREAM_BUFFER_KEY)
          return if buffer.nil? || buffer.empty?

          env.body = buffer
        end
      end

      ##
      # @return [ResponseGuard]
      attr_reader :response_guard

      # Executes the request with runtime policy enforcement, returning the normalized response.
      #
      # @return [Response] normalized response
      def perform_execute
        deadline = request_deadline
        @response_guard = ResponseGuard.new(policy: ctx.policy)
        reset_redirect_tracking!
        raw_response = request_with_terminal_redirect_retry(response_guard, deadline:)
        raw_response = retry_without_streaming(response_guard, deadline:) if retry_without_streaming?(raw_response)
        build_response(raw_response)
      end

      private

      def request_deadline
        monotonic_now + ctx.budget.effective_timeout_seconds(fallback: ctx.policy.total_timeout_seconds)
      end

      def reset_redirect_tracking!
        @last_redirect_to = nil
        @terminal_redirect_retried = false
        @request_url_override = nil
      end

      def request_with_terminal_redirect_retry(response_guard, deadline:)
        faraday_request(response_guard, deadline:, streaming_buffer: true)
      rescue Faraday::FollowRedirects::RedirectLimitReached => error
        raise error unless terminal_redirect_retryable?

        retry_from_terminal_redirect!(response_guard, deadline:)
      end

      def terminal_redirect_retryable?
        return false if @terminal_redirect_retried || @last_redirect_to.nil?

        @last_redirect_to.to_s != request_url.to_s
      end

      def retry_from_terminal_redirect!(response_guard, deadline:)
        terminal_url = @last_redirect_to
        @terminal_redirect_retried = true
        Log.debug("#{self.class}: redirect limit reached; retrying once from #{terminal_url}")
        begin_terminal_url_request!(terminal_url)
        faraday_request(response_guard, deadline:, streaming_buffer: true, consume_budget: false)
      end

      def begin_terminal_url_request!(terminal_url)
        ctx.policy.validate_request!(url: terminal_url, origin_url: ctx.origin_url, relation: ctx.relation)
        @request_url_override = terminal_url
        @client = nil
        @last_redirect_to = nil
      end

      def request_url
        @request_url_override || ctx.url
      end

      def build_response(response)
        Response.new(body: response.body, headers: response.headers, url: response_url(response),
                     status: response.status)
      end

      def faraday_request(response_guard, deadline:, streaming_buffer:, consume_budget: true)
        preflight!(consume_budget:)

        client.get do |req|
          apply_timeouts(req, deadline:)
          buffer = prepare_stream_buffer(req) if streaming_buffer
          req.options.on_data = on_data_callback(response_guard, buffer)
        end
      end

      def retry_without_streaming(response_guard, deadline:)
        faraday_request(response_guard, deadline:, streaming_buffer: false, consume_budget: false)
      end

      ##
      # Validates the remote socket peer IP during Net::HTTP start.
      module PeerIpValidator
        module_function

        # @param http [Net::HTTP] connection to configure
        # @param policy [Policy] request policy
        # @return [void]
        def install!(http, policy:)
          orig_start = http.method(:start)
          http.define_singleton_method(:start) do |&block|
            orig_start.call do |opened_http|
              PeerIpValidator.validate!(opened_http, policy:)
              block.call(opened_http)
            end
          end
        end

        # @param opened_http [Net::HTTP] active connection
        # @param policy [Policy] request policy
        # @return [void]
        def validate!(opened_http, policy:)
          scheme = opened_http.use_ssl? ? 'https' : 'http'
          url = Html2rss::Url.from_absolute("#{scheme}://#{opened_http.address}:#{opened_http.port}")
          policy.validate_remote_ip!(ip: peer_ip_for(opened_http), url:)
        end

        # @param opened_http [Net::HTTP]
        # @return [String, nil]
        def peer_ip_for(opened_http)
          sock = opened_http.instance_variable_get(:@socket)
          io = sock.respond_to?(:io) ? sock.io : sock
          peeraddr = io.respond_to?(:peeraddr) ? io.peeraddr : nil
          peeraddr&.[](3) || peeraddr&.[](2)
        end
      end

      # rubocop:disable Metrics/AbcSize
      def client
        @client ||= Faraday.new(url: request_url.to_s, headers: ctx.headers) do |faraday|
          faraday.use Faraday::FollowRedirects::Middleware, limit: ctx.policy.max_redirects, callback: redirect_callback
          faraday.request :gzip
          faraday.use StreamingBodyMiddleware
          faraday.adapter Faraday.default_adapter do |http|
            PeerIpValidator.install!(http, policy: ctx.policy)
          end
        end
      end
      # rubocop:enable Metrics/AbcSize

      def apply_timeouts(request, deadline:)
        remaining_timeout = remaining_timeout_seconds(deadline)
        request.options.timeout = remaining_timeout
        request.options.open_timeout = [ctx.policy.connect_timeout_seconds, remaining_timeout].min
        request.options.read_timeout = [ctx.policy.read_timeout_seconds, remaining_timeout].min
      end

      def prepare_stream_buffer(request)
        request.options.context ||= {}
        request.options.context[StreamingBodyMiddleware::STREAM_BUFFER_KEY] = +''
      end

      def on_data_callback(response_guard, buffer)
        proc do |chunk, total_bytes, env|
          response_guard.inspect_chunk!(total_bytes:, headers: env&.response_headers)
          buffer&.<< chunk
        end
      end

      def remaining_timeout_seconds(deadline)
        remaining = deadline - monotonic_now
        raise RequestTimedOut, 'Request timed out' if remaining <= 0

        remaining
      end

      def retry_without_streaming?(response)
        return false if response.body.to_s.empty? == false
        return false unless response_success?(response)

        final_url = response.env&.url
        return false unless final_url

        final_url.to_s != ctx.url.to_s
      end

      def response_success?(response)
        return true if response.status.nil?

        response.status >= 200 && response.status < 300
      end

      def response_url(response)
        return ctx.url unless (url = response.env&.url)

        Html2rss::Url.from_absolute(url.to_s)
      end

      def redirect_callback
        lambda do |old_env, new_env|
          from_url = normalize_url(old_env[:url])
          to_url = normalize_url(new_env[:url])
          @last_redirect_to = to_url
          ctx.policy.validate_redirect!(from_url:, to_url:, origin_url: ctx.origin_url, relation: ctx.relation)
        end
      end

      def normalize_url(url)
        Html2rss::Url.from_absolute(url.to_s)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
