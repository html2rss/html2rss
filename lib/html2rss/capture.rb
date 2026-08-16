# frozen_string_literal: true

module Html2rss
  ##
  # Analyzes a URL and produces a durable feed config: items selector + +enhance: true+.
  #
  # Fetches via {FeedPipeline} (including AutoFallback for +:auto+), extracts articles,
  # then derives a reusable items CSS selector from SST segments (list → cluster → semantic).
  class Capture # rubocop:disable Metrics/ClassLength -- segment strategies + CSS trim stay co-located
    LEADING_TRIM_TAGS = %w[html body].freeze
    private_constant :LEADING_TRIM_TAGS

    # Ordered Segmenter strategies tried until the items selector quality gate passes.
    SEGMENT_STRATEGIES = %i[list cluster semantic].freeze

    # Minimum matched segment/article pairs required to emit an items selector.
    MIN_SELECTOR_MATCHES = 2

    ##
    # Result of a capture operation (config plus quality meta).
    CaptureResult = Data.define(
      :config, :articles_count, :channel_title, :has_selectors, :segment_strategy,
      :admission_drops, :selected_strategy
    )

    class << self
      ##
      # Analyzes a URL and builds a reusable feed config.
      #
      # @param url [String] source page URL
      # @param strategy [Symbol] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @option options [String, nil] :items_selector optional selector hint
      # @option options [Integer, nil] :max_redirects optional redirect limit override
      # @option options [Integer, nil] :max_requests optional request budget override
      # @option options [Integer, nil] :limit max articles to keep
      # @option options [String, nil] :local_file_path optional local HTML file path
      # @return [CaptureResult]
      def build(url, strategy: :auto, **)
        new(url, strategy:, **).build
      end
    end

    ##
    # @param url [String] source page URL
    # @param strategy [Symbol] request strategy
    # @param options [Hash] additional options
    # @option options [String, nil] :items_selector optional selector hint
    # @option options [Integer, nil] :max_redirects optional redirect limit override
    # @option options [Integer, nil] :max_requests optional request budget override
    # @option options [Integer, nil] :limit max articles to keep
    # @option options [String, nil] :local_file_path optional local HTML file path
    def initialize(url, strategy: :auto, **options)
      @url = url
      @strategy = strategy
      @items_selector_hint = options.delete(:items_selector)
      @max_redirects = options.delete(:max_redirects)
      @max_requests = options.delete(:max_requests)
      @limit = options.delete(:limit)
      @local_file_path = options.delete(:local_file_path)
    end

    ##
    # Runs the capture pipeline.
    #
    # @return [CaptureResult]
    def build # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- outcome + selector + result assembly
      outcome = FeedPipeline.new(raw_config).to_outcome
      selectors, segment_strategy = derive_selectors(outcome.response, outcome.articles)

      config = {
        channel: build_channel(outcome.response),
        selectors: selectors.empty? ? nil : selectors,
        **strategy_stamp(outcome),
        **local_file_request_overlay
      }.compact

      CaptureResult.new(
        config:,
        articles_count: outcome.articles.size,
        channel_title: channel_title_from(outcome.response),
        has_selectors: !selectors.empty?,
        segment_strategy:,
        admission_drops: outcome.admission_drops,
        selected_strategy: outcome.selected_strategy
      )
    end

    private

    def strategy_stamp(outcome)
      concrete = outcome.selected_strategy || concrete_request_strategy
      return {} if concrete.nil? || concrete == :auto

      { strategy: concrete }
    end

    def concrete_request_strategy
      plan = FeedPipeline::StrategyPlan.resolve(@strategy)
      plan.is_a?(FeedPipeline::StrategyPlan::Concrete) ? plan.strategy : nil
    end

    def raw_config
      @raw_config ||= build_raw_config
    end

    def build_raw_config
      Config.auto_source_config(
        url: @url,
        items_selector: @items_selector_hint,
        request_controls: Config::RequestControls.from_shortcut(
          strategy: @strategy,
          max_redirects: @max_redirects,
          max_requests: @max_requests
        ),
        limit: @limit
      ).tap { |config| apply_local_file_path!(config) }
    end

    def apply_local_file_path!(config)
      return unless @local_file_path

      config[:strategy] = :local_file
      config[:request] ||= {}
      config[:request][:local_file_path] = @local_file_path
    end

    def local_file_request_overlay
      return {} unless @local_file_path

      { strategy: :local_file, request: { local_file_path: @local_file_path } }
    end

    # @return [Array(Hash, Symbol, nil)] selectors hash and winning segment strategy
    def derive_selectors(response, articles)
      return hint_selectors if @items_selector_hint
      return [{}, nil] if articles.empty? || !response.html_response?

      sst = SST::Normalizer.call(response.body)
      return [{}, nil] unless sst

      select_enhance_selectors(sst, articles)
    rescue ArgumentError => error
      Log.warn("Capture selector derivation failed: #{error.message}")
      [{}, nil]
    end

    def hint_selectors
      [{ items: { selector: @items_selector_hint, enhance: true } }, :hint]
    end

    def select_enhance_selectors(sst, articles) # rubocop:disable Metrics/MethodLength -- strategy loop + gate
      link_resolver = Scoring::LinkResolver.new(@url)

      SEGMENT_STRATEGIES.each do |strategy|
        segments = AutoSource::Segmenter.call(
          sst, base_url: @url, strategy:, permit_unanchored: false, link_resolver:
        )
        matched = match_segments_to_articles(segments, articles)
        items_sel = items_selector(matched)
        next unless items_sel && matched.size >= MIN_SELECTOR_MATCHES

        return [{ items: { selector: items_sel, enhance: true } }, strategy]
      end

      [{}, nil]
    end

    def match_segments_to_articles(segments, articles)
      articles_by_url = articles.each_with_object({}) do |article, hash|
        url_str = article.url.to_s
        hash[url_str] = article unless url_str.empty?
      end

      segments.filter_map do |segment|
        next unless segment.primary_link

        article = find_matching_article(segment, articles_by_url)
        { segment:, article: } if article
      end
    end

    def find_matching_article(segment, articles_by_url) # rubocop:disable Metrics/AbcSize
      href = segment.primary_link.attrs.href.to_s
      return articles_by_url.values.find { |a| a.title == title_from_segment(segment) } if href.empty?

      resolved = Url.from_relative(href, @url)
      articles_by_url[resolved.to_s] || articles_by_url.values.find { |a| fuzzy_url_match?(a.url, resolved) }
    end

    def fuzzy_url_match?(article_url, resolved)
      article_url.to_s.end_with?(resolved.path.to_s)
    rescue StandardError
      false
    end

    def title_from_segment(segment)
      segment.root_node.visible_text.to_s.strip
    end

    def items_selector(matched)
      return nil if matched.empty?

      roots = matched.map { |m| m[:segment].root_node }
      shared = shared_class_items_selector(roots)
      return shared if shared

      paths = roots.map(&:tag_path)
      common = common_path_prefix(paths)
      tag_path = common.empty? ? paths.first.to_s : common
      return nil if tag_path.empty?

      css_from_trimmed_tag_path(tag_path)
    end

    def shared_class_items_selector(roots)
      shared = roots.map { |root| root.attrs.class_names }.reduce { |left, right| left & right }
      return nil if shared.nil? || shared.empty?

      "#{roots.first.name}.#{shared.min}"
    end

    def css_from_trimmed_tag_path(tag_path)
      segments = tag_path.split('/').reject(&:empty?)
      trimmed = trim_leading_items_segments(segments)
      trimmed.join(' > ')
    end

    def trim_leading_items_segments(segments)
      return segments if segments.empty?

      trimmed = segments.dup
      trimmed.shift while trimmed.any? && LEADING_TRIM_TAGS.include?(trimmed.first)
      trimmed.shift while trimmed.length > 1 && trimmed.first == 'div'
      trimmed.empty? ? [segments.last] : trimmed
    end

    def common_path_prefix(paths) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      return '' if paths.empty?

      segments = paths.map { |p| p.split('/').reject(&:empty?) }
      prefix = segments.first
      segments.each do |seg|
        i = 0
        i += 1 while i < prefix.length && i < seg.length && prefix[i] == seg[i]
        prefix = prefix[0...i]
      end
      "/#{prefix.join('/')}"
    end

    def build_channel(response)
      {
        url: @url,
        title: channel_title_from(response),
        time_zone: 'UTC'
      }.compact
    end

    def channel_title_from(response)
      Channel.from_response(response).title
    rescue StandardError
      nil
    end
  end
end
