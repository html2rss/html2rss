# frozen_string_literal: true

module Html2rss
  ##
  # Analyzes a URL and produces a reusable feed config hash with derived CSS selectors.
  #
  # Uses the auto-source pipeline to extract articles, then traces back through
  # SST segments to build items + attribute selectors suitable for a static feed config.
  class Capture
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
      # @param options [Hash] additional options
      # @option options [String, nil] :items_selector optional selector hint
      # @option options [Integer, nil] :max_redirects optional redirect limit override
      # @option options [Integer, nil] :max_requests optional request budget override
      # @option options [Integer, nil] :limit max articles to keep
      # @return [CaptureResult]
      def build(url, strategy: :auto, **options)
        new(url, strategy:, **options).build
      end
    end

    ##
    # @param url [String] source page URL
    # @param strategy [Symbol] request strategy
    # @param options [Hash] additional options
    def initialize(url, strategy: :auto, **options)
      @url = url
      @strategy = strategy
      @items_selector_hint = options.delete(:items_selector)
      @max_redirects = options.delete(:max_redirects)
      @max_requests = options.delete(:max_requests)
      @limit = options.delete(:limit)
    end

    ##
    # Runs the capture pipeline.
    #
    # @return [CaptureResult]
    def build
      response = fetch_response
      articles = extract_articles(response)
      selectors = derive_selectors(response, articles)

      config = {
        channel: build_channel(response),
        selectors: selectors.empty? ? nil : selectors
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
      ).tap do |config|
        config[:strategy] = resolve_strategy(config[:strategy] || @strategy)
      end
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

    def derive_selectors(response, articles)
      return {} if articles.empty? || !response.html_response?

      sst = normalize_sst(response)
      return {} unless sst

      segments = discover_segments(sst)
      return {} if segments.empty?

      matched = match_segments_to_articles(segments, articles)
      return {} if matched.empty?

      build_selector_hash(matched, sst)
    rescue ArgumentError
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

    def find_matching_article(segment, articles_by_url)
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

    def build_selector_hash(matched, sst)
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
      paths = matched.map { |m| m[:segment].root_node.tag_path }
      common = common_path_prefix(paths)
      return paths.first.tr('/', ' ').strip.gsub(' ', ' > ') if common.empty?

      common.tr('/', ' ').strip.gsub(' ', ' > ')
    end

    def common_path_prefix(paths)
      return '' if paths.empty?

      segments = paths.map { |p| p.split('/').reject(&:empty?) }
      prefix = segments.first
      segments.each do |seg|
        i = 0
        while i < prefix.length && i < seg.length && prefix[i] == seg[i]
          i += 1
        end
        prefix = prefix[0...i]
      end
      "/#{prefix.join('/')}"
    end

    def title_selector(root)
      heading = root.find(&:heading?)
      return css_for_path(heading.tag_path, root.tag_path) if heading

      link = root.find { |n| n.link? && n.visible_text.to_s.strip.length > 3 }
      return css_for_path(link.tag_path, root.tag_path) if link

      nil
    end

    def link_selector(segment)
      return nil unless segment.primary_link

      relative = css_for_path(segment.primary_link.tag_path, segment.root_node.tag_path)
      { selector: relative, extractor: 'href' }
    end

    def description_selector(root, segment)
      relative = css_for_path(root.tag_path, segment.root_node.tag_path)
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