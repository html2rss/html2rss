# frozen_string_literal: true

require 'digest'
require 'uri'
require 'fileutils'

module Html2rss
  ##
  # Service that runs reconnaissance on a URL to discover redirect chains,
  # native RSS/Atom feeds, surface categorization, and emit an actionable verdict.
  module Recon # rubocop:disable Metrics/ModuleLength
    module_function

    ##
    # Closed curation verdict (:build / :defer / :drop).
    class Verdict
      # Closed set of curation verdict wire names.
      NAMES = Set[:build, :defer, :drop].freeze

      class << self
        ##
        # @param value [Verdict, Symbol, String]
        # @return [Verdict]
        def coerce(value)
          return value if value.is_a?(self)

          new(name: value.to_sym)
        end
      end

      ##
      # @return [Symbol]
      attr_reader :name

      ##
      # @param name [Symbol]
      def initialize(name:)
        raise ArgumentError, "unknown verdict: #{name.inspect}" unless NAMES.include?(name)

        @name = name
        freeze
      end

      ##
      # @return [Boolean]
      def build? = name == :build

      ##
      # @return [Boolean]
      def defer? = name == :defer

      ##
      # @return [Boolean]
      def drop? = name == :drop

      ##
      # @return [Symbol]
      def to_sym = name

      ##
      # @return [String]
      def to_s = name.to_s

      ##
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(self.class) && name == other.name
      end
      alias eql? ==

      ##
      # @return [Integer]
      def hash = [self.class, name].hash
    end

    ##
    # Immutable outcome of a reconnaissance operation.
    Result = Data.define(
      :requested_url,
      :final_url,
      :status,
      :verdict,
      :native_feed,
      :surface_category,
      :articles_count,
      :scheme_downgrade,
      :notes,
      :html_bytesize
    ) do
      ##
      # @return [Boolean]
      def build? = verdict.build?

      ##
      # @return [Boolean]
      def defer? = verdict.defer?

      ##
      # @return [Boolean]
      def drop? = verdict.drop?

      ##
      # @return [Boolean]
      def native_feed? = !native_feed.nil?

      ##
      # @return [Hash{Symbol => Object}]
      def to_h # rubocop:disable Metrics/MethodLength
        {
          requested_url: requested_url.to_s,
          final_url: final_url.to_s,
          status:,
          verdict: verdict.to_sym,
          native_feed: native_feed&.to_s,
          surface_category: surface_category&.to_s,
          articles_count:,
          scheme_downgrade:,
          notes:,
          html_bytesize:
        }.compact
      end
    end

    ##
    # Runs reconnaissance on a single URL.
    #
    # @param url [String, Html2rss::Url] source page URL
    # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
    # @param cache_dir [String, nil] optional directory to cache raw HTML bodies
    # @param cache_mutex [Mutex, nil] optional mutex serializing cache writes
    # @option options [Integer, nil] :max_redirects optional maximum redirects
    # @option options [Integer, nil] :max_requests optional request budget
    # @return [Html2rss::Recon::Result]
    def call(url, strategy: :auto, cache_dir: nil, cache_mutex: nil, **) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      url_obj = Url.from_absolute(url)

      begin
        probe = PageRecon.probe(url_obj, strategy:, **)
      rescue StandardError => error
        return error_result(url_obj, error)
      end

      cache_html_body(probe.response.body, url_obj, cache_dir, cache_mutex) if cache_dir && probe.response.body

      recon = probe.result
      native_feed = find_native_feed(url_obj, probe.session, probe.response)
      notes = build_notes(recon, native_feed, probe.response)
      verdict = determine_verdict(recon, native_feed)

      Result.new(
        requested_url: url_obj,
        final_url: probe.response.url,
        status: probe.response.status,
        verdict:,
        native_feed:,
        surface_category: SurfaceCategory.coerce(recon.surface_category),
        articles_count: recon.articles_count,
        scheme_downgrade: recon.scheme_downgrade,
        notes:,
        html_bytesize: probe.response.body&.bytesize
      )
    end

    ##
    # Runs batch reconnaissance across an Enumerable of URLs.
    # Results are returned in input order. Concurrency uses a Thread pool
    # (not Ractors) for I/O overlap with one loaded gem image.
    #
    # @param urls [Enumerable<String>] list of URLs
    # @param strategy [Symbol] request strategy
    # @param cache_dir [String, nil] optional directory to cache raw HTML bodies
    # @param max_threads [Integer] concurrent worker count
    # @option options [Integer, nil] :max_redirects optional maximum redirects
    # @option options [Integer, nil] :max_requests optional request budget
    # @return [Array<Html2rss::Recon::Result>]
    def batch(urls, strategy: :auto, cache_dir: nil, max_threads: 5, **options) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
      url_list = urls.map { |u| u.to_s.strip }.reject(&:empty?)
      return [] if url_list.empty?

      FileUtils.mkdir_p(cache_dir) if cache_dir
      results = Array.new(url_list.size)
      cache_mutex = Mutex.new
      queue = Queue.new
      url_list.each_with_index { |u, i| queue << [i, u] }

      worker_count = [max_threads, url_list.size].min
      threads = Array.new(worker_count) do
        Thread.new do # rubocop:disable ThreadSafety/NewThread
          loop do
            index, target_url = begin
              queue.pop(true)
            rescue ThreadError
              break
            end

            results[index] = call(target_url, strategy:, cache_dir:, cache_mutex:, **options)
          end
        end
      end
      threads.each(&:join)
      results
    end

    ##
    # @param url_obj [Html2rss::Url]
    # @param session [Html2rss::RequestSession]
    # @param response [Html2rss::RequestService::Response]
    # @return [Html2rss::Url, nil]
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

    def determine_verdict(recon, native_feed)
      return Verdict.coerce(:drop) if recon.status.nil? || recon.status >= 400 || recon.scheme_downgrade
      return Verdict.coerce(:defer) if native_feed

      category = SurfaceCategory.coerce(recon.surface_category)
      return Verdict.coerce(:drop) if category.blocked?

      Verdict.coerce(:build)
    end
    private_class_method :determine_verdict

    def error_result(url_obj, error) # rubocop:disable Metrics/MethodLength
      Result.new(
        requested_url: url_obj,
        final_url: url_obj,
        status: nil,
        verdict: Verdict.coerce(:drop),
        native_feed: nil,
        surface_category: SurfaceCategory.coerce(:unsupported_surface),
        articles_count: 0,
        scheme_downgrade: false,
        notes: ["error: #{error.class} - #{error.message}"],
        html_bytesize: nil
      )
    end
    private_class_method :error_result

    # Writes the raw response body once under a host+url-digest filename.
    #
    # @param body [String]
    # @param url_obj [Html2rss::Url]
    # @param cache_dir [String]
    # @param cache_mutex [Mutex, nil]
    # @return [void]
    def cache_html_body(body, url_obj, cache_dir, cache_mutex)
      host = url_obj.host.to_s.delete_prefix('www.')
      host = 'snapshot' if host.empty?
      digest = Digest::SHA256.hexdigest(url_obj.to_s)[0, 12]
      file_path = File.join(cache_dir, "#{host}-#{digest}.html")
      writer = -> { File.write(file_path, body) }
      cache_mutex ? cache_mutex.synchronize(&writer) : writer.call
    rescue StandardError => error
      Log.debug("Recon cache failed: #{error.message}")
    end
    private_class_method :cache_html_body
  end
end
