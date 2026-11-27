# frozen_string_literal: true

module Html2rss
  module Extraction
    ##
    # The follow-ups of one pass, as the scrapers see them: the object they call {#follow_up} on in place of a
    # request session. It does no I/O: an answered request is replayed from +responses+, any other is recorded as
    # wanted and ends that scraper's pass, for the host to fetch and call the kernel again.
    class Exchange
      # A failed request the host reported as +{error_kind:}+.
      class RequestFailed < Html2rss::Error
        # @param kind [Symbol] the {ErrorKind} name
        def initialize(kind)
          @kind = kind
          super("follow-up request failed (#{kind})")
        end

        # @return [Symbol]
        attr_reader :kind
      end

      # One wanted follow-up; +id+ (+"<relation> <url>"+) keys its answer in +responses+.
      Request = Data.define(:id, :url, :relation, :origin_url)

      # Ends a pass; private, so no other +catch+ can intercept a pending request.
      PENDING = Object.new.freeze
      private_constant :PENDING

      ##
      # @param response [Html2rss::RequestService::Response]
      # @return [Hash{Symbol => Object}] its entry in +responses+
      def self.answer(response)
        { url: response.url.to_s, status: response.status, headers: response.headers, body: response.body }
      end

      ##
      # @param error [Html2rss::Error] a failed follow-up
      # @return [Hash{Symbol => Object}] its entry in +responses+
      def self.failure(error) = { error_kind: error.kind }

      ##
      # @param entry [Hash{Symbol => Object}] an {.answer}, or a page: +:url+, +:body+, optional +:headers+
      # @return [Html2rss::RequestService::Response]
      def self.response(entry)
        RequestService::Response.new(body: entry.fetch(:body), url: Url.from_absolute(entry.fetch(:url)),
                                     headers: entry[:headers], status: entry[:status])
      end

      ##
      # @param responses [Hash{String => Hash}] every answer so far, by request id
      # @param cap [Integer] the most requests the kernel may ask for in all
      def initialize(responses:, cap:)
        @responses = responses
        @cap = cap
        @wanted = {}
      end

      # @return [Array<Request>] the requests wanted and not yet answered
      def requests = @wanted.values

      # @yieldreturn [Object] a scraper's pass
      # @return [Object, nil] its result, nil when it asked for an unanswered request
      def guard(&) = catch(PENDING, &)

      ##
      # The call of {Html2rss::RequestSession#follow_up}, answered from +responses+.
      #
      # @param url [String, Html2rss::Url]
      # @param relation [Symbol]
      # @param origin_url [String, Html2rss::Url]
      # @return [Html2rss::RequestService::Response]
      # @raise [RequestService::RequestBudgetExceeded] beyond the cap, or when the host reported +:budget+
      # @raise [RequestFailed] when the host reported the request as failed
      def follow_up(url:, relation:, origin_url:, **)
        url = Url.from_absolute(url)
        request = Request.new(id: "#{relation} #{url}", url: url.to_s, relation:,
                              origin_url: Url.from_absolute(origin_url).to_s)
        entry = @responses[request.id] || wish(request)
        return self.class.response(entry) unless entry.key?(:error_kind)

        raise_failure(ErrorKind[entry[:error_kind]].to_sym)
      end

      private

      def wish(request)
        raise_failure(:budget) if @responses.size + @wanted.size >= @cap && !@wanted.key?(request.id)

        @wanted[request.id] = request
        throw PENDING
      end

      def raise_failure(kind)
        raise RequestService::RequestBudgetExceeded, 'Request budget exhausted' if kind == :budget

        raise RequestFailed, kind
      end
    end
  end
end
