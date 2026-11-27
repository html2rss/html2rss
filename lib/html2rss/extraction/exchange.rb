# frozen_string_literal: true

module Html2rss
  module Extraction
    ##
    # What the scrapers call {#follow_up} on in place of a request session. No I/O: an answered request is replayed
    # from +responses+, any other is recorded as wanted and ends that scraper's pass.
    class Exchange
      # A failed request the host reported with an +:error_kind+.
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

      # Private, so no other +catch+ can intercept a pending request.
      PENDING = Object.new.freeze
      private_constant :PENDING

      ##
      # @param entry [Hash{Symbol => Object}] an answer in +responses+ (or a page): +:url+, +:body+, and
      #   optionally +:headers+ and +:status+; a failed request is a lone +:error_kind+ instead
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
      # {Html2rss::RequestSession#follow_up}, answered from +responses+.
      #
      # @param url [String, Html2rss::Url]
      # @param relation [Symbol]
      # @param origin_url [String, Html2rss::Url]
      # @return [Html2rss::RequestService::Response]
      # @raise [RequestService::RequestBudgetExceeded] beyond the cap, and only then
      # @raise [RequestFailed] when the host reported the request as failed, whatever its kind
      def follow_up(url:, relation:, origin_url:, **)
        url = Url.from_absolute(url)
        request = Request.new(id: "#{relation} #{url}", url: url.to_s, relation:,
                              origin_url: origin_url.to_s)
        entry = @responses[request.id] || wish(request)
        kind = entry[:error_kind]
        raise RequestFailed, kind if kind

        self.class.response(entry)
      end

      private

      # Spends a slot by distinct URL: the host's session answers one URL under two relations from one request.
      def wish(request)
        raise RequestService::RequestBudgetExceeded, 'Request budget exhausted' if over_cap?(request)

        @wanted[request.id] = request
        throw PENDING
      end

      def over_cap?(request)
        urls = (@responses.keys + @wanted.keys).to_set { _1.split(' ', 2).last }
        urls.size >= @cap && !urls.include?(request.url)
      end
    end
  end
end
