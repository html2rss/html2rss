# frozen_string_literal: true

require 'time'

module Html2rss
  ##
  # The extraction kernel (experimental): an HTML page and its absolute URL in, plain data out, no I/O.
  #
  # Runs the auto-source scrapers over the one page it is given. A scraper that needs a follow-up fetch
  # (native feed, WordPress API, sitemap, oEmbed) makes the kernel answer +:needs_requests+ with the requests it
  # wants; the host fetches them under its own policy and calls again with every answer so far. The kernel never
  # reads a clock or a network: +now+ is an input. See CONTEXT.md § Extraction kernel.
  module Extraction
    ##
    # What one pass over a page found: the articles as objects, or the follow-ups it still wants.
    # +articles+ are empty while +requests+ are wanted.
    Outcome = Data.define(:articles, :admission_drops, :feed_channel, :requests)

    ##
    # @param page [Hash{Symbol => Object}] the page as an {Exchange.answer} entry: +:url+ (absolute), +:body+ and
    #   optionally +:headers+ (+content-type+, +content-language+; UTF-8 HTML when absent)
    # @param now [String] the current time, ISO 8601; the kernel reads no clock
    # @param responses [Hash{String => Hash}] every follow-up answer so far, by request id ({Exchange})
    # @param options [Hash] the auto-source options ({AutoSource.options})
    # @option options [Integer, nil] :limit max articles to keep
    # @option options [Boolean, nil] :keep_different_domain overrides cleanup.keep_different_domain
    # @option options [Boolean, nil] :keep_sponsored overrides cleanup.keep_sponsored
    # @return [Result] articles as plain data, the requests still wanted, or the {ErrorKind} of the failure
    # @raise [Html2rss::ContractError] on a programmer error
    # @raise [InvalidOption] when an option is invalid
    def self.call(page:, now:, responses: {}, **)
      clock = AutoSource::Clock.new(now: parse_now(now), time_zone: nil)
      response = Exchange.response({ headers: RequestService::Response::HTML_HEADERS, **page })
      outcome = run(response:, options: AutoSource.options(**), clock:, responses:)
      return Result.needs_requests(outcome.requests) if outcome.requests.any?

      Result.ok(with_url_dates(without_shared_categories(without_tracking(unique(outcome.articles))), clock))
    rescue ContractError, InvalidOption
      raise
    rescue Html2rss::Error => error
      Result.failure(error)
    end

    ##
    # One pass of the auto-source scrapers over +response+, the one path of the gem and of the kernel.
    #
    # @param response [Html2rss::RequestService::Response] the page
    # @param options [Hash] validated auto-source options ({AutoSource.options})
    # @param clock [AutoSource::Clock] the run's time
    # @param responses [Hash{String => Hash}] follow-up answers so far, by request id
    # @param channel [Hash{Symbol => Object}] channel overrides (an explicit +:language+ wins)
    # @return [Outcome]
    def self.run(response:, options:, clock:, responses: {}, channel: {})
      exchange = Exchange.new(responses:, cap: AutoSource.request_slots_for(options))
      vocabulary = Vocabulary[Channel.language_for(response, channel)]
      source = AutoSource.new(response, options, exchange:, vocabulary:, clock:)
      Outcome.new(articles: source.articles, admission_drops: source.admission_drops,
                  feed_channel: source.feed_channel, requests: exchange.requests)
    end

    ##
    # The host's loop over {.run}: fetches every request a pass wants through +session+ and runs again with
    # every answer so far, until nothing is wanted. The one loop of the gem and of the specs; all I/O and every
    # network policy stay in +session+.
    #
    # @param response [Html2rss::RequestService::Response] the page
    # @param options [Hash] validated auto-source options ({AutoSource.options})
    # @param clock [AutoSource::Clock] the run's time
    # @param session [#follow_up] a {Html2rss::RequestSession}, or any object with its +follow_up+
    # @param channel [Hash{Symbol => Object}] channel overrides (an explicit +:language+ wins)
    # @return [Outcome] the last pass: its articles, no requests left
    def self.drive(response:, options:, clock:, session:, channel: {})
      responses = {}
      loop do
        outcome = run(response:, options:, clock:, responses:, channel:)
        return outcome if outcome.requests.empty?

        outcome.requests.each { responses[_1.id] = Exchange.fetch(_1, response, session) }
      end
    end

    ##
    # @param now [String] ISO 8601 time
    # @return [Time]
    # @raise [InvalidOption] when +now+ is not an ISO 8601 time
    def self.parse_now(now)
      Time.iso8601(now.to_s)
    rescue ArgumentError
      raise InvalidOption, "now must be an ISO 8601 time, got #{now.inspect}"
    end
    private_class_method :parse_now

    ##
    # Deduplicates +articles+ and keeps the first +limit+: the one owner of +limit+ across paths (selector,
    # auto-source and syndication articles are capped together).
    #
    # @param articles [Array<Html2rss::Article>]
    # @param limit [Integer, nil] max articles to keep (nil keeps all; {AutoSource} already caps its own)
    # @return [Array<Html2rss::Article>]
    def self.unique(articles, limit: nil)
      unique = Article::Deduplicator.new(articles).call
      limit ? unique.first(limit) : unique
    end

    ##
    # The one owner of tracking-suffix removal on item URLs, for every path (HTML, selectors, feeds).
    # The guid hashes the url, so an item that carried a suffix gets a new guid once.
    #
    # @param articles [Array<Html2rss::Article>]
    # @return [Array<Html2rss::Article>] +articles+ with {Url#without_tracking_params} applied to each URL
    def self.without_tracking(articles)
      articles.map do |article|
        url = article.url
        clean = url&.without_tracking_params
        clean.equal?(url) ? article : article.with_url(clean)
      end
    end

    ##
    # The one owner of the item-wide category rule for every path: a category all items share is dropped.
    # A publisher's native feed states its own categories, so its items are left as they are.
    #
    # @param articles [Array<Html2rss::Article>]
    # @return [Array<Html2rss::Article>] +articles+ with categories shared by every item removed
    def self.without_shared_categories(articles)
      return articles if articles.any? { |article| article.scraper == AutoSource::Scraper::NativeFeed }

      kept = AutoSource::ArticleRules::Category.drop_shared(articles.map(&:categories))
      articles.zip(kept).map do |article, categories|
        categories == article.categories ? article : article.with_categories(categories)
      end
    end

    ##
    # The single owner of the URL-path date fallback: it runs on the final articles, after cross-scraper
    # merge and dedup, so no earlier stage (card walk, merge, scoring) ever sees a URL date.
    #
    # @param articles [Array<Html2rss::Article>]
    # @param clock [AutoSource::Clock] the run's time: the zone dates are read in and the bound of a plausible one
    # @return [Array<Html2rss::Article>] +articles+, each undated one dated by its URL path when it names one
    def self.with_url_dates(articles, clock)
      articles.map do |article|
        next article if article.published_at

        date = AutoSource::ArticleRules::UrlDate.call(article.url, time_zone: clock.time_zone, now: clock.now)
        date ? article.with_published_at(date) : article
      end
    end
  end
end
