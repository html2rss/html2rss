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

    # Value object representing the outcome of a batch operation.
    BatchResult = Data.define(:total, :successful, :results) do
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
        list = Array(items)
        return [] if list.empty?

        worker_count = worker_pool_size(list.size, concurrency)
        process_queue(list, worker_count, &)
      end

      ##
      # Runs a batch operation that yields items and wraps the results in a {BatchResult}.
      #
      # @param items [Enumerable<Object>]
      # @param concurrency [Integer] max parallel worker threads (1..10, default: 5)
      # @yieldparam item [Object]
      # @return [BatchResult]
      def run(items, concurrency: DEFAULT_CONCURRENCY, &)
        list = Array(items)
        results = map(list, concurrency:, &)
        successful = results.count { |entry| entry.is_a?(Hash) ? entry[:ok] : !entry.nil? }

        BatchResult.new(total: list.size, successful:, results:)
      end

      ##
      # Scrapes multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Enumerable<String>] list of URLs to scrape
      # @param strategy [Symbol, String] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @param limit [Integer] max articles to extract per URL
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @return [BatchResult]
      def batch_scrape(urls:, strategy: :auto, limit: 10, concurrency: DEFAULT_CONCURRENCY)
        run(urls, concurrency:) { |url| scrape_single_url(url:, strategy:, limit:) }
      end

      ##
      # Inspects multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Enumerable<String>] list of URLs to inspect
      # @param strategy [Symbol, String] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @return [BatchResult]
      def batch_inspect(urls:, strategy: :auto, concurrency: DEFAULT_CONCURRENCY)
        reports = PageRecon::Diagnostics.batch(urls:, strategy:, concurrency:)
        results = reports.map(&:to_wire_h)
        successful = reports.count { |report| diagnostic_success?(report) }

        BatchResult.new(total: results.size, successful:, results:)
      end

      ##
      # Runs recon across multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Enumerable<String>] list of URLs to recon
      # @param strategy [Symbol, String] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @option options [String, nil] :cache_dir optional HTML cache directory
      # @return [BatchResult]
      def batch_recon(urls:, strategy: :auto, concurrency: DEFAULT_CONCURRENCY, **options)
        results = Recon.batch(urls, strategy: (strategy || :auto).to_sym, max_threads: concurrency, **options)
        successful = results.count { |r| r.status ? r.status < 400 : false }
        BatchResult.new(total: results.size, successful:, results: results.map(&:to_h))
      end

      private

      def diagnostic_success?(report)
        status = report.to_wire_h[:status]
        status ? status < 400 : false
      end

      def scrape_single_url(url:, strategy:, limit:)
        plan = (strategy || :auto).to_sym
        feed = Html2rss.auto_feed_result(url, strategy: plan, limit:).to_json_feed
        items = feed[:items] || []
        { url: url.to_s, ok: true, items_count: items.size, items:, channel_title: feed[:title] }
      rescue StandardError => error
        { url: url.to_s, ok: false, error: error.message }
      end

      def worker_pool_size(item_count, requested_concurrency)
        return 1 if item_count <= 1

        [[1, requested_concurrency.to_i].max, item_count, MAX_CONCURRENCY].min
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
