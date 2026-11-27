# frozen_string_literal: true

module Html2rss
  module Curation
    ##
    # Concurrency-bounded batch execution over enumerables with input order preservation
    # and per-item error isolation.
    module Batch
      # Maximum permitted worker threads for batch operations.
      MAX_CONCURRENCY = 10
      # Default worker threads for batch operations.
      DEFAULT_CONCURRENCY = 5

      BatchResult = Data.define(:total, :successful, :results, :errors)

      ##
      # Outcome of a batch operation. +errors+ holds the exception behind each failed row (nil elsewhere, same
      # order as +results+) for callers that classify failures; it is not part of the wire +to_h+.
      class BatchResult
        # @param total [Integer]
        # @param successful [Integer]
        # @param results [Array<Object>] rows; a row's +:failure+ exception moves into +errors+
        # @param errors [Array<Exception, nil>] defaults to the rows' +:failure+ values
        def initialize(total:, successful:, results:, errors: results.map { |row| row[:failure] if row.is_a?(Hash) })
          super(total:, successful:, errors:,
                results: results.map { |row| row.is_a?(Hash) ? row.except(:failure) : row })
        end

        ##
        # @return [Hash{Symbol => Object}] +:total+, +:successful+, +:results+
        def to_h(&) = super.except(:errors)
      end

      class << self
        ##
        # Executes a block concurrently across items using a bounded worker pool.
        # Results are returned in input order.
        #
        # @param items [Enumerable<Object>]
        # @param concurrency [Integer] max parallel worker threads (1..10, default: 5)
        # @yieldparam item [Object]
        # @return [Array<Object>]
        def map(items, concurrency: DEFAULT_CONCURRENCY, &)
          Option.integer(:concurrency, concurrency, min: 1, max: MAX_CONCURRENCY)
          process_queue(Option.list(:items, items), [concurrency, items.size].min, &)
        end

        ##
        # Runs a batch operation that yields items and wraps the results in a {BatchResult}.
        #
        # @param items [Enumerable<Object>]
        # @param concurrency [Integer] max parallel worker threads (1..10, default: 5)
        # @yieldparam item [Object]
        # @return [BatchResult]
        def run(items, concurrency: DEFAULT_CONCURRENCY, &)
          results = map(items, concurrency:, &)
          successful = results.count { |entry| entry.is_a?(Hash) ? entry[:ok] : !entry.nil? }

          BatchResult.new(total: items.size, successful:, results:)
        end

        ##
        # Single-URL scrape wire extraction: Html2rss.scrape → JSON Feed items.
        #
        # @param url [String]
        # @param strategy [Symbol, String]
        # @param limit [Integer]
        # @param items_selector [String, nil]
        # @param resolution_scope [String, Symbol, nil] +section+ or +site+
        # @return [Hash{Symbol => Object}] +:strategy+, +:items+, +:channel_title+, +:admission_drops+,
        #   +:scrape_url+ and, only when entry resolution was applied or kept the entry for lack of an in-scope
        #   winner, +:entry_resolution+
        def scrape_wire(url:, strategy:, limit:, items_selector: nil, resolution_scope: nil)
          plan = FeedPipeline::StrategyPlan.coerce(strategy)
          feed_result = Html2rss.scrape(url, strategy: plan, limit:, **{ items_selector:, resolution_scope: }.compact)
          feed = feed_result.to_json_feed
          {
            strategy: plan,
            items: feed[:items] || [],
            channel_title: feed[:title],
            admission_drops: feed_result.status.admission_drops,
            **page_wire(feed_result.status, url)
          }
        end

        ##
        # Scrapes multiple URLs in parallel with per-URL error isolation.
        #
        # @param urls [Enumerable<String>] list of URLs to scrape
        # @param strategy [Symbol, String] request strategy (+:auto+, +:default+, +:botasaurus+)
        # @param limit [Integer] max articles to extract per URL
        # @param concurrency [Integer] number of worker threads (default 5, max 10)
        # @param resolution_scope [String, Symbol, nil] +section+ or +site+
        # @return [BatchResult]
        def batch_scrape(urls:, strategy: :auto, limit: 10, concurrency: DEFAULT_CONCURRENCY, resolution_scope: nil)
          strategy = FeedPipeline::StrategyPlan.coerce(strategy)
          Option.integer(:limit, limit, min: 1)
          run(Option.list(:urls, urls), concurrency:) do |url|
            scrape_single_url(url:, strategy:, limit:, resolution_scope:)
          end
        end

        ##
        # Inspects multiple URLs in parallel with per-URL error isolation.
        #
        # @param urls [Enumerable<String>] list of URLs to inspect
        # @param strategy [Symbol, String] request strategy (+:auto+, +:default+, +:botasaurus+)
        # @param concurrency [Integer] number of worker threads (default 5, max 10)
        # @return [BatchResult]
        def batch_inspect(urls:, strategy: :auto, concurrency: DEFAULT_CONCURRENCY)
          plan = FeedPipeline::StrategyPlan.coerce(strategy)
          reports = Inspect.batch(urls: Option.list(:urls, urls), strategy: plan, concurrency:)
          results = reports.map(&:to_wire_h)
          successful = reports.count { |report| diagnostic_success?(report) }

          BatchResult.new(total: results.size, successful:, results:)
        end

        ##
        # Runs recon across multiple URLs in parallel with per-URL error isolation.
        #
        # @param urls [Enumerable<String>] list of URLs to recon
        # @param strategy [Symbol, String] request strategy (+:auto+, +:default+, +:botasaurus+)
        # @param concurrency [Integer] number of worker threads (default 5, max 10)
        # @option options [String, nil] :cache_dir optional HTML cache directory
        # @return [BatchResult]
        def batch_recon(urls:, strategy: :auto, concurrency: DEFAULT_CONCURRENCY, **)
          Option.integer(:concurrency, concurrency, min: 1, max: MAX_CONCURRENCY)
          results = Recon.batch(Option.list(:urls, urls), strategy: FeedPipeline::StrategyPlan.coerce(strategy),
                                                          max_threads: concurrency, **)
          successful = results.count { |result| http_success?(result.status) }
          BatchResult.new(total: results.size, successful:, results: results.map(&:to_h))
        end

        private

        def diagnostic_success?(report)
          http_success?(report.to_wire_h[:status])
        end

        def http_success?(status)
          !status.nil? && status < 400
        end

        # The page the items came from: entry resolution may swap the requested URL for a better page or feed,
        # or keep it when every better page lay outside the requested section.
        def page_wire(status, requested_url)
          wire = { scrape_url: status.scrape_url || requested_url.to_s }
          resolution = status.entry_resolution
          kept = resolution&.[](:reason) == :no_in_scope_winner
          wire[:entry_resolution] = resolution if resolution&.[](:applied) || kept
          wire
        end

        def scrape_single_url(url:, strategy:, limit:, resolution_scope: nil)
          wire = scrape_wire(url:, strategy:, limit:, resolution_scope:)
          {
            url: url.to_s, ok: true, items_count: wire.fetch(:items).size,
            items: wire.fetch(:items), channel_title: wire.fetch(:channel_title),
            **wire.slice(:scrape_url, :entry_resolution)
          }
        rescue Html2rss::ContractError
          raise
        rescue Html2rss::Error => error
          { url: url.to_s, ok: false, error: error.message, failure: error }
        end

        def process_queue(items, worker_count, &)
          queue = build_work_queue(items)
          results = Array.new(items.size)

          threads = Array.new(worker_count) do
            Thread.new { drain_queue(queue, results, &) } # rubocop:disable ThreadSafety/NewThread
          end
          threads.each(&:join)
          results
        end

        def build_work_queue(items)
          Queue.new.tap do |queue|
            items.each_with_index { |item, index| queue << [item, index] }
          end
        end

        def drain_queue(queue, results)
          loop do
            begin
              item, index = queue.pop(true)
            rescue ThreadError
              break
            end
            results[index] = yield(item)
          end
        end
      end
    end
  end
end
