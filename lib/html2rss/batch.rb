# frozen_string_literal: true

module Html2rss
  ##
  # Concurrency-bounded batch execution over enumerables with input order preservation
  # and per-item error isolation.
  module Batch
    # Maximum permitted worker threads for batch operations.
    MAX_CONCURRENCY = 10
    # Default worker threads for batch operations.
    DEFAULT_CONCURRENCY = 5

    BatchResult = Data.define(:total, :successful, :results)

    # Value object representing the outcome of a batch operation.
    class BatchResult
      ##
      # @return [Hash{Symbol => Object}]
      def to_h
        { total:, successful:, results: }
      end
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
      # Single-URL scrape wire extraction: auto_feed_result → JSON Feed items.
      #
      # @param url [String]
      # @param strategy [Symbol, String]
      # @param limit [Integer]
      # @param items_selector [String, nil]
      # @return [Hash{Symbol => Object}] +:strategy+, +:items+, +:channel_title+, +:admission_drops+
      def scrape_wire(url:, strategy:, limit:, items_selector: nil) # rubocop:disable Metrics/MethodLength
        plan = Option.strategy(strategy)
        feed_args = { strategy: plan, limit: }
        feed_args[:items_selector] = items_selector unless items_selector.nil?
        feed_result = Html2rss.auto_feed_result(url, **feed_args)
        feed = feed_result.to_json_feed
        {
          strategy: plan,
          items: feed[:items] || [],
          channel_title: feed[:title],
          admission_drops: feed_result.status.admission_drops
        }
      end

      ##
      # Scrapes multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Enumerable<String>] list of URLs to scrape
      # @param strategy [Symbol, String] request strategy (+:auto+, +:default+, +:botasaurus+)
      # @param limit [Integer] max articles to extract per URL
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @return [BatchResult]
      def batch_scrape(urls:, strategy: :auto, limit: 10, concurrency: DEFAULT_CONCURRENCY)
        strategy = Option.strategy(strategy)
        Option.integer(:limit, limit, min: 1)
        run(Option.list(:urls, urls), concurrency:) { |url| scrape_single_url(url:, strategy:, limit:) }
      end

      ##
      # Inspects multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Enumerable<String>] list of URLs to inspect
      # @param strategy [Symbol, String] request strategy (+:auto+, +:default+, +:botasaurus+)
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @return [BatchResult]
      def batch_inspect(urls:, strategy: :auto, concurrency: DEFAULT_CONCURRENCY)
        reports = PageRecon::Diagnostics.batch(urls: Option.list(:urls, urls), strategy: Option.strategy(strategy),
                                               concurrency:)
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
        results = Recon.batch(Option.list(:urls, urls), strategy: Option.strategy(strategy),
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

      def scrape_single_url(url:, strategy:, limit:)
        wire = scrape_wire(url:, strategy:, limit:)
        {
          url: url.to_s, ok: true, items_count: wire[:items].size,
          items: wire[:items], channel_title: wire[:channel_title]
        }
      rescue Html2rss::Error => error
        { url: url.to_s, ok: false, error: error.message }
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
        until queue.empty?
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
