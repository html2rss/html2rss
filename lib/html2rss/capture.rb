# frozen_string_literal: true

module Html2rss
  ##
  # Analyzes a URL and produces a durable feed config: items selector + metadata.
  #
  # Fetches via {FeedPipeline} (including AutoFallback for +:auto+), extracts articles,
  # derives reusable items CSS selectors from SST segments, and infers directory catalog metadata.
  #
  # {include:file:lib/html2rss/capture/README.md}
  class Capture # rubocop:disable Metrics/ClassLength -- segment strategies + CSS trim stay co-located
    LEADING_TRIM_TAGS = %w[html body].freeze
    private_constant :LEADING_TRIM_TAGS

    # Packaged YAML language server modeline.
    SCHEMA_MODELINE = '# yaml-language-server: $schema=https://raw.githubusercontent.com/html2rss/html2rss/refs/heads/master/schema/html2rss-config.schema.json'

    # Ordered Segmenter strategies tried until the items selector quality gate passes.
    SEGMENT_STRATEGIES = %i[list cluster semantic].freeze

    # Minimum matched segment/article pairs required to emit an items selector.
    MIN_SELECTOR_MATCHES = 2

    ##
    # Result of a capture operation (config plus quality meta).
    CaptureResult = Data.define(
      :config, :yaml, :articles_count, :channel_title, :has_selectors, :segment_strategy,
      :admission_drops, :selected_strategy, :inferred_topics, :native_feed
    ) do
      # rubocop:disable Metrics/ParameterLists
      ##
      # @param config [Hash]
      # @param articles_count [Integer]
      # @param channel_title [String]
      # @param has_selectors [Boolean]
      # @param segment_strategy [Symbol]
      # @param yaml [String, nil]
      # @param admission_drops [Hash]
      # @param selected_strategy [Symbol, nil]
      # @param inferred_topics [Array<String>]
      # @param native_feed [String, nil]
      def initialize(config:, articles_count:, channel_title:, has_selectors:, segment_strategy:, # rubocop:disable Metrics/MethodLength
                     yaml: nil, admission_drops: {}, selected_strategy: nil, inferred_topics: [], native_feed: nil)
        super(
          config:,
          yaml: yaml || "#{SCHEMA_MODELINE}\n#{Config.to_yaml(config)}",
          articles_count:,
          channel_title:,
          has_selectors:,
          segment_strategy:,
          admission_drops:,
          selected_strategy:,
          inferred_topics:,
          native_feed:
        )
      end
      # rubocop:enable Metrics/ParameterLists

      ##
      # @return [Boolean] whether first-party RSS was detected
      def native_feed?
        !native_feed.nil?
      end
      alias_method :has_native_feed?, :native_feed?
    end

    class << self
      ##
      # Analyzes a URL and builds a reusable feed config.
      #
      # @param url [String] source page URL
      # @param strategy [Symbol] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @option options [String, nil] :items_selector optional selector hint
      # @option options [Array<String>, nil] :topics optional directory topics override
      # @option options [String, nil] :title optional title override
      # @option options [String, nil] :summary optional summary override
      # @option options [Boolean] :force whether to ignore native feed detection
      # @option options [Boolean, nil] :enhance whether to force enhance: true
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
    # @option options [String, nil] :items_selector optional selector hint
    # @option options [Array<String>, nil] :topics optional directory topics override
    # @option options [String, nil] :title optional title override
    # @option options [String, nil] :summary optional summary override
    # @option options [Boolean] :force whether to ignore native feed detection
    # @option options [Boolean, nil] :enhance whether to force enhance: true
    # @option options [Integer, nil] :max_redirects optional redirect limit override
    # @option options [Integer, nil] :max_requests optional request budget override
    # @option options [Integer, nil] :limit max articles to keep
    # @option options [String, nil] :local_file_path optional local HTML file path
    def initialize(url, strategy: :auto, **options) # rubocop:disable Metrics/MethodLength
      @url = url
      @strategy = strategy
      @items_selector_hint = options.delete(:items_selector)
      @topics = options.delete(:topics)
      @title = options.delete(:title)
      @summary = options.delete(:summary)
      @force = options.delete(:force) || false
      @enhance_option = options.delete(:enhance)
      @max_redirects = options.delete(:max_redirects)
      @max_requests = options.delete(:max_requests)
      @limit = options.delete(:limit)
      @local_file_path = options.delete(:local_file_path)
    end

    ##
    # Runs the capture pipeline.
    #
    # @return [CaptureResult]
    def build # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      outcome = FeedPipeline.new(raw_config).to_outcome
      selectors, segment_strategy = derive_selectors(outcome.response, outcome.articles)
      ch_title = @title || channel_title_from(outcome.response)
      topics = @topics || infer_topics("#{@url} #{ch_title}")
      native_feed = probe_native_feed(outcome.response) unless @force

      config = {
        directory: build_directory(ch_title, topics),
        channel: build_channel(outcome.response, ch_title),
        selectors: selectors.empty? ? nil : selectors,
        **strategy_stamp(outcome),
        **local_file_request_overlay
      }.compact

      CaptureResult.new(
        config:,
        yaml: "#{SCHEMA_MODELINE}\n#{Config.to_yaml(config)}",
        articles_count: outcome.articles.size,
        channel_title: ch_title,
        has_selectors: !selectors.empty?,
        segment_strategy:,
        admission_drops: outcome.admission_drops,
        selected_strategy: outcome.selected_strategy,
        inferred_topics: topics,
        native_feed:
      )
    end

    private

    def build_directory(title, topics)
      summary_text = @summary || "#{title} updates and announcements."
      {
        topics: topics.take(2),
        title:,
        summary: summary_text[0, 160]
      }.compact
    end

    def probe_native_feed(response)
      return nil unless response&.html_response? && @url

      parsed = response.parsed_body
      return nil unless parsed.is_a?(Nokogiri::HTML::Document)

      links = Html::FeedLink.from_document(parsed)
      links.first&.href
    rescue StandardError
      nil
    end

    def infer_topics(text) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/MethodLength
      t = text.to_s.downcase
      inferred = []
      inferred << 'tech' if /tech|developer|software|cloud|api|compute|ai|data|model|hardware|cyber/.match?(t)
      inferred << 'security' if /security|vulnerab|advis|threat|breach|cve|cert|patch/.match?(t)
      inferred << 'science' if /science|space|astron|physics|bio|research|institut|discover|nature/.match?(t)
      inferred << 'energy' if /energy|wind|solar|power|grid|renewab|oil|gas|hydro/.match?(t)
      inferred << 'finance' if /financ|bank|invest|monetary|market|regulat|treasury|econom/.match?(t)
      inferred << 'civic' if /govern|policy|council|parliament|court|treaty|public/.match?(t)
      inferred << 'environment' if /climat|environ|planet|sustainab|carbon|ecolog|earth/.match?(t)
      inferred << 'consumer' if /consum|recall|safety|rating|test|product/.match?(t)
      inferred << 'travel' if /travel|touris|destination|trip|flight|hotel|transit|rail/.match?(t)
      inferred << 'sports' if /sport|olympic|racing|football|soccer|tennis|game/.match?(t)
      inferred << 'health' if /health|medic|pharma|hospital|disease|patient/.match?(t)
      inferred << 'education' if /educat|universit|school|student|academi|learn/.match?(t)
      inferred << 'transport' if /transport|traffic|automotive|vehicle|train|bus/.match?(t)
      valid = inferred.select { |topic| Config::Validator::DIRECTORY_TOPICS.include?(topic) }
      valid.empty? ? ['news'] : valid.first(2)
    end

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
      enhance = @enhance_option.nil? || @enhance_option
      [{ items: { selector: @items_selector_hint, enhance: } }, :hint]
    end

    def select_enhance_selectors(sst, articles) # rubocop:disable Metrics/MethodLength -- strategy loop + gate
      link_resolver = Scoring::LinkResolver.new(@url)
      enhance = @enhance_option.nil? || @enhance_option

      SEGMENT_STRATEGIES.each do |strategy|
        segments = AutoSource::Segmenter.call(
          sst, base_url: @url, strategy:, permit_unanchored: false, link_resolver:
        )
        matched = match_segments_to_articles(segments, articles)
        items_sel = items_selector(matched)
        next unless items_sel && matched.size >= MIN_SELECTOR_MATCHES

        return [{ items: { selector: items_sel, enhance: } }, strategy]
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

      roots = lift_heading_link_roots(matched.map { |m| m[:segment].root_node })
      shared = shared_class_items_selector(roots)
      return shared if shared

      paths = roots.map(&:tag_path)
      common = common_path_prefix(paths)
      tag_path = common.empty? ? paths.first.to_s : common
      return nil if tag_path.empty?

      css_from_trimmed_tag_path(tag_path)
    end

    def lift_heading_link_roots(roots)
      roots.map { |root| lift_heading_link_root(root, roots) }
    end

    def lift_heading_link_root(root, all_roots)
      return root unless heading_or_inner_title_link?(root)

      index = SST::Index.for_node(root)
      return root unless index

      walk_usable_card(root, index, all_roots)
    end

    def walk_usable_card(root, index, all_roots)
      candidate = root
      parent = index.parent_of(root)
      while parent && Html::Navigator.usable_card_parent?(parent)
        break if contains_other_root?(parent, root, all_roots)

        candidate = parent
        parent = index.parent_of(parent)
      end
      candidate
    end

    def heading_or_inner_title_link?(node)
      name = node.name.to_s
      return false if wrapping_anchor_root?(node)

      Html::Navigator::HEADING_TAGS.include?(name) || name == 'a'
    end

    def wrapping_anchor_root?(node)
      return false unless node.name.to_s == 'a'
      return false unless node.respond_to?(:find)

      tags = Html::Navigator::WRAPPING_ANCHOR_CHILD_TAGS
      node.find { |child| !child.equal?(node) && tags.include?(child.name.to_s) }
    end

    def contains_other_root?(parent, root, all_roots)
      all_roots.any? do |other|
        next if other.equal?(root)

        other.equal?(parent) || sst_descendant?(other, parent)
      end
    end

    def sst_descendant?(child, ancestor)
      SST::Index.for_node(child)&.descendant_of?(child, ancestor)
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

    def build_channel(response, title = nil)
      {
        url: @url,
        title: title || channel_title_from(response),
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
