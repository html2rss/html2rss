# frozen_string_literal: true

module Html2rss
  module Extraction
    ##
    # The follow-up requests of one extraction pass, as the scrapers see them: the one object a scraper calls
    # {#follow_up} on, in place of a transport session. It performs no I/O. A request whose answer the host passed
    # in +responses+ is replayed; any other is recorded as wanted and ends that scraper's pass for this round.
    # The host fetches the wanted requests under its own policy and calls the kernel again with every answer so far.
    class Exchange
      # Raised in place of a failed request the host reports as +{error_kind:}+; carries only the kind.
      class RequestFailed < Html2rss::Error
        # @param kind [Symbol] the {Html2rss::ErrorKind} name of the failure
        def initialize(kind)
          @kind = kind
          super("follow-up request failed (#{kind})")
        end

        # @return [Symbol]
        attr_reader :kind
      end

      ##
      # One follow-up the kernel wants fetched. +id+ keys the answer in the next call: +"<relation> <url>"+.
      # The host decides whether, and how, to fetch it.
      Request = Data.define(:id, :url, :relation, :origin_url)

      # What {#guard} catches: private to the exchange, so no other +catch+ can intercept a pending request.
      PENDING = Object.new.freeze
      private_constant :PENDING

      ##
      # @param response [Html2rss::RequestService::Response] a fetched follow-up
      # @return [Hash{Symbol => Object}] its entry in +responses+
      def self.answer(response)
        { url: response.url.to_s, status: response.status, headers: response.headers, body: response.body }
      end

      ##
      # @param entry [Hash{Symbol => Object}] an {.answer}, or a page: +:url+, +:body+, optional +:headers+, +:status+
      # @return [Html2rss::RequestService::Response]
      def self.response(entry)
        RequestService::Response.new(
          body: entry.fetch(:body), url: Url.from_absolute(entry.fetch(:url)), headers: entry[:headers],
          status: entry[:status]
        )
      end

      ##
      # The host side of one wanted request: fetches it through +session+ (which keeps every network policy)
      # and returns its entry for +responses+.
      #
      # @param request [Request]
      # @param page [Html2rss::RequestService::Response] the page the request came from
      # @param session [#follow_up] a {Html2rss::RequestSession}, or any object with its +follow_up+
      # @return [Hash{Symbol => Object}] an {.answer}, or a {.failure} when the fetch raised an {Html2rss::Error}
      def self.fetch(request, page, session)
        # A feed the page advertises may leave the page origin: that proof is rebuilt here, never taken from a request.
        advertisement = if request.relation == :advertised_feed
                          RequestService::FeedAdvertisement.from_document(page.parsed_body, page_url: page.url)
                        end
        answer(session.follow_up(url: request.url, relation: request.relation, origin_url: request.origin_url,
                                 advertisement:))
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error => error
        failure(error)
      end

      ##
      # @param error [Html2rss::Error] a follow-up that failed
      # @return [Hash{Symbol => Object}] its entry in +responses+
      def self.failure(error) = { error_kind: error.kind }

      ##
      # @param responses [Hash{String => Hash}] request id => an {.answer} or {.failure} entry, every answer so far
      # @param cap [Integer] the most requests the kernel may ask for in all
      def initialize(responses:, cap:)
        @responses = responses
        @cap = cap
        @wanted = {}
      end

      # @return [Array<Request>] the requests wanted and not yet answered
      def requests = @wanted.values

      # @return [Boolean] whether some request is wanted
      def pending? = @wanted.any?

      ##
      # Runs a scraper's pass; ends it quietly when it asks for a request that is not answered yet.
      #
      # @yieldreturn [Object]
      # @return [Object, nil] the block's result, nil when the pass ended
      def guard(&) = catch(PENDING, &)

      ##
      # The follow-up a scraper makes; the same call as {Html2rss::RequestSession#follow_up}.
      #
      # @param url [String, Html2rss::Url]
      # @param relation [Symbol] why the follow-up is made
      # @param origin_url [String, Html2rss::Url]
      # @return [Html2rss::RequestService::Response] the replayed answer
      # @raise [Html2rss::RequestService::RequestBudgetExceeded] beyond the cap
      # @raise [RequestFailed] when the host reported the request as failed
      def follow_up(url:, relation:, origin_url:, **)
        url = Url.from_absolute(url)
        request = Request.new(id: "#{relation} #{url}", url: url.to_s, relation:,
                              origin_url: Url.from_absolute(origin_url).to_s)
        return replay(@responses.fetch(request.id)) if @responses.key?(request.id)

        wish(request)
      end

      private

      def wish(request)
        if @responses.size + @wanted.size >= @cap && !@wanted.key?(request.id)
          raise RequestService::RequestBudgetExceeded, 'Request budget exhausted'
        end

        @wanted[request.id] = request
        throw PENDING
      end

      def replay(entry)
        return self.class.response(entry) unless entry.key?(:error_kind)

        kind = ErrorKind[entry[:error_kind]].to_sym
        raise RequestService::RequestBudgetExceeded, 'Request budget exhausted' if kind == :budget

        raise RequestFailed, kind
      end
    end
  end
end
