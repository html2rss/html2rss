# frozen_string_literal: true

require 'uri'
require 'fileutils'

module Html2rss
  ##
  # Service that runs reconnaissance on a URL to discover redirect chains,
  # native RSS/Atom feeds, surface categorization, and emit an actionable verdict.
  module Recon # rubocop:disable Metrics/ModuleLength
    module_function

    ##
    # Runs reconnaissance on a single URL.
    #
    # @param url [String, Html2rss::Url] source page URL
    # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
    # @option options [Integer, nil] :max_redirects optional maximum redirects
    # @option options [Integer, nil] :max_requests optional request budget
    # @return [Html2rss::ReconResult]
    def call(url, strategy: :auto, **) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      url_obj = Url.from_absolute(url)
      resolved_strategy = FeedPipeline::StrategyPlan.concrete_for_diagnostic(strategy)

      session, response, error = fetch_initial(url_obj, resolved_strategy, **)
      return error_result(url_obj, error) if error

      recon = PageRecon.call(response:, url: url_obj, strategy: resolved_strategy)
      native_feed = find_native_feed(url_obj, session, response) || recon.alternate_feeds.first&.dig(:href)
      notes = build_notes(recon, native_feed, response)
      verdict = determine_verdict(recon, native_feed, error)

      ReconResult.new(
        requested_url: url_obj,
        final_url: response.url,
        status: response.status,
        verdict:,
        native_feed:,
        surface_category: SurfaceCategory.coerce(recon.surface_category),
        articles_count: recon.articles_count,
        scheme_downgrade: recon.scheme_downgrade,
        notes:,
        redirect_chain: [url_obj.to_s, response.url.to_s].uniq,
        html_bytesize: response.body&.bytesize
      )
    end

    ##
    # Runs batch reconnaissance across an Enumerable of URLs.
    #
    # @param urls [Enumerable<String>] list of URLs
    # @param strategy [Symbol] request strategy
    # @param cache_dir [String, nil] optional directory to cache raw HTML bodies
    # @param max_threads [Integer] concurrent worker count
    # @option options [Integer, nil] :max_redirects optional maximum redirects
    # @option options [Integer, nil] :max_requests optional request budget
    # @return [Array<Html2rss::ReconResult>]
    def batch(urls, strategy: :auto, cache_dir: nil, max_threads: 5, **options) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      FileUtils.mkdir_p(cache_dir) if cache_dir
      results = []
      mutex = Mutex.new

      queue = Queue.new
      urls.each { |u| queue << u.to_s.strip }

      threads = Array.new([max_threads, queue.size].min) do
        Thread.new do # rubocop:disable ThreadSafety/NewThread
          until queue.empty?
            target_url = begin
              queue.pop(true)
            rescue ThreadError
              nil
            end
            break unless target_url
            next if target_url.empty?

            res = call(target_url, strategy:, **options)
            cache_html_snapshot(res, cache_dir) if cache_dir
            mutex.synchronize { results << res }
          end
        end
      end
      threads.each(&:join)
      results
    end

    ##
    # @param url_obj [Html2rss::Url]
    # @param strategy [Symbol]
    # @option options [Integer, nil] :max_redirects
    # @option options [Integer, nil] :max_requests
    # @return [Array(Html2rss::RequestSession, Html2rss::RequestService::Response, StandardError)]
    def fetch_initial(url_obj, strategy, **options) # rubocop:disable Metrics/MethodLength
      raw_config = Config.auto_source_config(
        url: url_obj.to_s,
        request_controls: Config::RequestControls.from_shortcut(
          strategy:,
          max_redirects: options[:max_redirects],
          max_requests: options[:max_requests]
        )
      )
      raw_config[:strategy] = strategy
      config = Config.from_hash(raw_config)
      resources = FeedPipeline::RuntimePolicy.resources_for(config)
      session = RequestSession.build(
        config:,
        strategy: config.strategy,
        budget: resources.budget,
        policy: resources.policy
      )
      [session, session.fetch_initial_response, nil]
    rescue StandardError => error
      [nil, nil, error]
    end
    private_class_method :fetch_initial

    def find_native_feed(url_obj, session, response)
      Syndication::Discovery.best_feed_url(
        page_url: url_obj,
        request_session: session,
        parsed_body: (response.parsed_body if response.html_response?),
        html: response.body
      )
    rescue StandardError
      nil
    end
    private_class_method :find_native_feed

    def build_notes(recon, native_feed, response)
      notes = []
      notes << "native_rss=#{native_feed}" if native_feed
      notes << 'scheme_downgrade' if recon.scheme_downgrade
      notes << "blocked=#{recon.blocked_surface}" if recon.blocked_surface
      notes << "html_bytes=#{response.body&.bytesize}" if response.body
      notes
    end
    private_class_method :build_notes

    def determine_verdict(recon, native_feed, error)
      return :drop if error || recon.status.nil? || recon.status >= 400 || recon.scheme_downgrade
      return :defer if native_feed

      category = SurfaceCategory.coerce(recon.surface_category)
      return :drop if category.blocked?

      :build
    end
    private_class_method :determine_verdict

    def error_result(url_obj, error) # rubocop:disable Metrics/MethodLength
      ReconResult.new(
        requested_url: url_obj,
        final_url: url_obj,
        status: nil,
        verdict: :drop,
        native_feed: nil,
        surface_category: SurfaceCategory.coerce(:unsupported_surface),
        articles_count: 0,
        scheme_downgrade: false,
        notes: ["error: #{error.class} - #{error.message}"],
        redirect_chain: [url_obj.to_s],
        html_bytesize: nil
      )
    end
    private_class_method :error_result

    def cache_html_snapshot(result, cache_dir)
      slug = result.final_url.host.to_s.delete_prefix('www.')
      slug = 'snapshot' if slug.empty?
      file_path = File.join(cache_dir, "#{slug}.html")
      File.write(file_path, result.notes.join("\n"))
    rescue StandardError => error
      Log.debug("Recon cache failed: #{error.message}")
    end
    private_class_method :cache_html_snapshot
  end
end
