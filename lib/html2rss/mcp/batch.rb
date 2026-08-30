# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Concurrency-bounded batch execution over URLs with per-URL error isolation.
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

      module_function

      ##
      # Inspects multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Array<String>] list of URLs to inspect
      # @param strategy [Symbol, String] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @return [BatchResult]
      def inspect_urls(urls:, strategy: :auto, concurrency: DEFAULT_CONCURRENCY)
        run_batch(urls, concurrency:) { |url| inspect_single_url(url:, strategy:) }
      end

      ##
      # Scrapes multiple URLs in parallel with per-URL error isolation.
      #
      # @param urls [Array<String>] list of URLs to scrape
      # @param strategy [Symbol, String] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @param limit [Integer] max articles to extract per URL
      # @param concurrency [Integer] number of worker threads (default 5, max 10)
      # @return [BatchResult]
      def scrape_urls(urls:, strategy: :auto, limit: 10, concurrency: DEFAULT_CONCURRENCY)
        run_batch(urls, concurrency:) { |url| scrape_single_url(url:, strategy:, limit:) }
      end

      ##
      # @param url [String]
      # @param strategy [Symbol, String]
      # @return [Hash]
      def inspect_single_url(url:, strategy:)
        recon = Inspect.call(url:, strategy:)
        {
          url:,
          ok: true,
          status_code: recon[:status],
          final_url: recon[:final_url] || url,
          alternate_feeds: Array(recon[:alternate_feeds])
        }
      rescue StandardError => error
        { url:, ok: false, error: error.message }
      end
      module_function :inspect_single_url
      private_class_method :inspect_single_url

      ##
      # @param url [String]
      # @param strategy [Symbol, String]
      # @param limit [Integer]
      # @return [Hash]
      def scrape_single_url(url:, strategy:, limit:)
        plan = (strategy || :auto).to_sym
        feed_result = Html2rss.auto_feed_result(url, strategy: plan, limit:)
        feed = feed_result.to_json_feed
        scrape_success_payload(url, feed)
      rescue StandardError => error
        { url:, ok: false, error: error.message }
      end
      module_function :scrape_single_url
      private_class_method :scrape_single_url

      def scrape_success_payload(url, feed)
        items = feed[:items] || []
        { url:, ok: true, items_count: items.size, items:, channel_title: feed[:title] }
      end
      module_function :scrape_success_payload
      private_class_method :scrape_success_payload

      ##
      # Dispatches work across a bounded pool of worker threads.
      #
      # @param items [Array<Object>]
      # @param concurrency [Integer]
      # @return [BatchResult]
      def run_batch(items, concurrency:, &)
        list = Array(items)
        worker_count = worker_pool_size(list.size, concurrency)
        results = process_queue(list, worker_count, &)

        successful = results.count { |entry| entry[:ok] }
        BatchResult.new(total: list.size, successful:, results:)
      end
      module_function :run_batch
      private_class_method :run_batch

      def worker_pool_size(item_count, requested_concurrency)
        return 1 if item_count <= 1

        [[1, requested_concurrency.to_i].max, item_count, MAX_CONCURRENCY].min
      end
      module_function :worker_pool_size
      private_class_method :worker_pool_size

      def process_queue(items, worker_count, &)
        queue = build_work_queue(items)
        results = Array.new(items.size)

        threads = Array.new(worker_count) do
          Thread.new { drain_queue(queue, results, &) } # rubocop:disable ThreadSafety/NewThread
        end
        threads.each(&:join)
        results
      end
      module_function :process_queue
      private_class_method :process_queue

      def build_work_queue(items)
        Queue.new.tap do |queue|
          items.each_with_index { |item, index| queue << [item, index] }
        end
      end
      module_function :build_work_queue
      private_class_method :build_work_queue

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
      module_function :drain_queue
      private_class_method :drain_queue
    end
  end
end
