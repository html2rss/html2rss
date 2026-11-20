# frozen_string_literal: true

require 'cgi'

module Html2rss
  class Article
    ##
    # Opt-in feed-build step and the single owner of "metadata from an article page": for items missing
    # +published_at+, +author+ or +image+ it fetches the item's own page and fills only those fields from the
    # page's JSON-LD and meta tags. Listing values are never overwritten; body text and description are never read.
    #
    # Fetches go through a {RequestSession} sub-allowance, so strategy, policy (same-origin rule, network guard,
    # response size cap) and headers match the listing fetch. The allowance is separate from the listing
    # budget, so one build makes at most {MAX_TOTAL_REQUESTS} requests: the listing budget
    # ({RequestService::Policy::MAX_REQUESTS_CEILING}) plus {MAX_FETCHES}. A blocked or failed fetch leaves the
    # item unchanged and is counted; enrichment never fails the build.
    class Enrichment
      # Hard maximum and default number of article fetches per feed build.
      MAX_FETCHES = 10
      # Upper bound on requests one build can make: listing budget plus the enrichment allowance.
      MAX_TOTAL_REQUESTS = RequestService::Policy::MAX_REQUESTS_CEILING + MAX_FETCHES
      # Per field an article page can supply: how to read it from an article and how to set it.
      FIELDS = {
        published_at: [->(article) { article.published_at }, ->(article, value) { article.with_published_at(value) }],
        author: [->(article) { article.author }, ->(article, value) { article.with_author(value) }],
        image: [->(article) { article.image }, ->(article, value) { article.with_image(value) }]
      }.freeze
      # Meta tag keys per field, in precedence order.
      META_KEYS = {
        published_at: %w[article:published_time],
        author: %w[article:author author],
        image: %w[og:image]
      }.freeze
      # Result of one run. +tally+ keys: enriched (items that gained a field), enrich_failed (fetches that
      # failed or were blocked, including cross-origin skips), enrich_skipped_cross_origin (the policy-denied subset).
      Result = Data.define(:articles, :tally)

      class << self
        ##
        # @param articles [Array<Html2rss::Article>] deduplicated articles
        # @param request_session [Html2rss::RequestSession] the listing session (strategy and policy are reused)
        # @param max_fetches [Integer] article fetch cap, clamped to {MAX_FETCHES}
        # @return [Result] the articles (unchanged ones kept in place) and the enrichment tally
        def call(articles, request_session:, max_fetches: MAX_FETCHES)
          cap = max_fetches.clamp(1, MAX_FETCHES)
          new(request_session.with_budget_allowance(cap), cap).call(articles)
        end
      end

      # @param session [Html2rss::RequestSession] session with the enrichment request allowance
      # @param cap [Integer] maximum article fetches
      def initialize(session, cap)
        @session = session
        @cap = cap
        @tally = Hash.new(0)
      end

      # @param articles [Array<Html2rss::Article>]
      # @return [Result]
      def call(articles)
        budget = @cap
        enriched = articles.map do |article|
          next article unless budget.positive? && candidate?(article)

          budget -= 1
          enrich(article)
        end
        Result.new(articles: enriched, tally: @tally.slice(:enriched, :enrich_failed, :enrich_skipped_cross_origin))
      end

      private

      def candidate?(article)
        article.url && FIELDS.each_value.any? { |read, _| read.call(article).nil? }
      end

      def enrich(article)
        response = fetch(article.url)
        return failed(article) unless page?(response)

        fill(article, page_metadata(response))
      rescue RequestService::CrossOriginFollowUpDenied
        @tally[:enrich_skipped_cross_origin] += 1
        failed(article)
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error, JSON::ParserError
        failed(article)
      end

      # Sets only the fields the article lacks; counts the article when any was set.
      def fill(article, found)
        filled = FIELDS.reduce(article) do |current, (field, (read, write))|
          read.call(current).nil? && found[field] ? write.call(current, found.fetch(field)) : current
        end
        @tally[:enriched] += 1 unless filled.equal?(article)
        filled
      end

      def failed(article)
        @tally[:enrich_failed] += 1
        article
      end

      def fetch(url)
        @session.follow_up(url:, relation: :auto_source, origin_url: @session.url)
      end

      def page?(response)
        (response.status.nil? || response.status.between?(200, 299)) && response.html_response?
      end

      def page_metadata(response)
        document = response.parsed_body
        things = jsonld_things(document, response.url)
        FIELDS.keys.to_h { |field| [field, jsonld_value(things, field) || meta_value(document, field, response.url)] }
      end

      def jsonld_things(document, url)
        document.css('script[type="application/ld+json"]').flat_map do |script|
          schema = AutoSource::Scraper::Schema
          schema.from_script(script).select { schema.scraper_for_schema_object(_1) == schema::Thing }
                .map { schema::Thing.new(_1, url:) }
        rescue JSON::ParserError
          []
        end
      end

      def jsonld_value(things, field)
        things.each do |thing|
          next if field == :author && !thing.schema_object[:author]

          value = thing_value(thing, field).to_s.strip
          return value unless value.empty?
        end
        nil
      end

      def thing_value(thing, field)
        case field
        when :published_at then thing.published_at
        when :author then thing.author
        else thing.image
        end
      end

      def meta_value(document, field, base)
        META_KEYS.fetch(field).each do |key|
          value = document.at_css("meta[property='#{key}'], meta[name='#{key}']")&.[]('content').to_s.strip
          next if value.empty? || (field == :author && value.include?('://'))

          return field == :image ? Url.from_relative(value, base).to_s : value
        end
        nil
      end
    end
  end
end
