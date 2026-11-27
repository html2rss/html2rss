# frozen_string_literal: true

module Html2rss
  ##
  # The extraction kernel (experimental): an HTML string and its absolute URL in, plain data out, no I/O.
  #
  # Runs the auto-source scrapers over the one page it is given. A scraper that needs a follow-up fetch
  # (native feed, WordPress API, sitemap, entry resolution) finds nothing here; the host owns every request.
  # See CONTEXT.md § Extraction kernel.
  module Extraction
    # Channel time zone the URL-path date fallback reads, as {Config.default_config} sets it.
    TIME_ZONE = 'UTC'
    private_constant :TIME_ZONE

    ##
    # @param html [String] the page body
    # @param url [String, Html2rss::Url] the page's absolute URL
    # @option options [Integer, nil] :limit max articles to keep
    # @option options [Boolean, nil] :keep_different_domain overrides cleanup.keep_different_domain
    # @option options [Boolean, nil] :keep_sponsored overrides cleanup.keep_sponsored
    # @return [Result] articles as plain data, or the {ErrorKind} of the failure
    # @raise [Html2rss::ContractError] on a programmer error
    # @raise [InvalidOption] when an option is invalid
    def self.call(html:, url:, **)
      auto_source = AutoSource.options(**)
      response = RequestService::Response.local_html(body: html, url:)
      Result.ok(extract(response, auto_source))
    rescue ContractError, InvalidOption
      raise
    rescue Html2rss::Error => error
      Result.failure(error)
    end

    ##
    # Deduplicates +articles+ and keeps the first +limit+: the one owner of +limit+ across paths (selector,
    # auto-source and syndication articles are capped together).
    #
    # @param articles [Array<Html2rss::Article>]
    # @param limit [Integer, nil] max articles to keep (nil keeps all)
    # @return [Array<Html2rss::Article>]
    def self.unique(articles, limit:)
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
    # @param time_zone [String] channel time zone
    # @return [Array<Html2rss::Article>] +articles+, each undated one dated by its URL path when it names one
    def self.with_url_dates(articles, time_zone)
      articles.map do |article|
        next article if article.published_at

        date = AutoSource::ArticleRules::UrlDate.call(article.url, time_zone:)
        date ? article.with_published_at(date) : article
      end
    end

    # @return [Array<Html2rss::Article>]
    def self.extract(response, auto_source)
      vocabulary = Vocabulary[Channel.language_for(response)]
      articles = AutoSource.new(response, auto_source, vocabulary:).articles
      kept = without_shared_categories(without_tracking(unique(articles, limit: auto_source[:limit])))
      with_url_dates(kept, TIME_ZONE)
    end
    private_class_method :extract
  end
end
