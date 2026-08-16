# frozen_string_literal: true

module Html2rss
  ##
  # Analyzes a URL and produces a reusable feed config hash with derived CSS selectors.
  #
  # Uses the auto-source pipeline to extract articles, then traces back through
  # SST segments to build items + attribute selectors suitable for a static feed config.
  class Capture # rubocop:disable Metrics/ClassLength
    LEADING_TRIM_TAGS = %w[html body].freeze
    private_constant :LEADING_TRIM_TAGS

    ##
    # Result of a capture operation.
    # @!attribute config [Hash] feed config hash with +:channel+ and +:selectors+
    # @!attribute articles_count [Integer] number of articles extracted
    # @!attribute channel_title [String] derived channel title
    CaptureResult = Data.define(:config, :articles_count, :channel_title)

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
    def build # rubocop:disable Metrics/MethodLength
      response = fetch_response
      articles = extract_articles(response)
      selectors = derive_selectors(response, articles)

      config = {
        channel: build_channel(response),
        selectors: selectors.empty? ? nil : selectors,
        **local_file_request_overlay
      }.compact

      CaptureResult.new(
        config:,
        articles_count: articles.size,
        channel_title: channel_title_from(response)
      )
    end

    private

    def raw_config
      @raw_config ||= build_raw_config
    end

    def build_raw_config # rubocop:disable Metrics/MethodLength
      Config.auto_source_config(
        url: @url,
        items_selector: @items_selector_hint,
        request_controls: Config::RequestControls.from_shortcut(
          strategy: @strategy,
          max_redirects: @max_redirects,
          max_requests: @max_requests
        ),
        limit: @limit
      ).tap do |config|
        config[:strategy] = resolve_strategy(config[:strategy] || @strategy)
        apply_local_file_path!(config)
      end
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

    def resolve_strategy(strategy)
      plan = FeedPipeline::StrategyPlan.resolve(strategy)
      plan.is_a?(FeedPipeline::StrategyPlan::Auto) ? :faraday : plan.strategy
    end

    def fetch_response
      config = Config.from_hash(raw_config)
      resources = FeedPipeline::RuntimePolicy.resources_for(config)
      session = RequestSession.build(
        config:,
        strategy: config.strategy,
        budget: resources.budget,
        policy: resources.policy
      )
      session.fetch_initial_response
    end

    def extract_articles(response)
      auto_source_opts = raw_config[:auto_source] || AutoSource::DEFAULT_CONFIG
      AutoSource.new(response, auto_source_opts).articles
    rescue AutoSource::Scraper::NoScraperFound
      []
    end

    def derive_selectors(response, articles) # rubocop:disable Metrics/MethodLength
      return {} if articles.empty? || !response.html_response?

      sst = normalize_sst(response)
      return {} unless sst

      segments = discover_segments(sst)
      return {} if segments.empty?

      matched = match_segments_to_articles(segments, articles)
      return {} if matched.empty?

      build_selector_hash(matched, sst)
    rescue ArgumentError => error
      Log.warn("Capture selector derivation failed: #{error.message}")
      {}
    end

    def normalize_sst(response)
      SST::Normalizer.call(response.body)
    end

    def discover_segments(sst)
      link_resolver = Scoring::LinkResolver.new(@url)

      AutoSource::Segmenter.call(
        sst,
        base_url: @url,
        strategy: :list,
        permit_unanchored: false,
        link_resolver:
      )
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

    def build_selector_hash(matched, _sst)
      items_sel = items_selector(matched)
      return {} unless items_sel

      first = matched.first
      root = first[:segment].root_node

      attrs = {}.tap do |a|
        a[:title] = title_selector(root)
        a[:link] = link_selector(first[:segment])
        a[:description] = description_selector(root, first[:segment])
      end.compact

      { items: { selector: items_sel }, **attrs }
    end

    def items_selector(matched)
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

    def title_selector(root) # rubocop:disable Metrics/CyclomaticComplexity
      heading = root.find(&:heading?)
      relative = css_for_path(heading.tag_path, root.tag_path) if heading
      relative ||= begin
        link = root.find { |n| n.link? && n.visible_text.to_s.strip.length > 3 }
        css_for_path(link.tag_path, root.tag_path) if link
      end
      return nil unless relative

      { selector: relative }
    end

    def link_selector(segment)
      return nil unless segment.primary_link

      relative = css_for_path(segment.primary_link.tag_path, segment.root_node.tag_path)
      { selector: relative, extractor: 'href' }
    end

    def description_selector(root, segment)
      relative = css_for_path(root.tag_path, segment.root_node.tag_path)
      return nil if relative.nil? || relative.empty? || relative == '.'

      { selector: relative }
    end

    def css_for_path(full_path, root_path)
      relative = full_path.delete_prefix(root_path)
      return '.' if relative.empty?

      relative.split('/').reject(&:empty?).join(' > ')
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
