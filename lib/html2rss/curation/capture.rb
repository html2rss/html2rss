# frozen_string_literal: true

module Html2rss
  module Curation
    ##
    # Analyzes a URL and produces a durable feed config: items selector + metadata.
    #
    # Fetches via {FeedPipeline} (including AutoFallback for +:auto+), extracts articles,
    # derives reusable items CSS selectors from SST segments, and infers directory catalog metadata.
    #
    # {include:file:lib/html2rss/curation/capture/README.md}
    class Capture # rubocop:disable Metrics/ClassLength -- segment strategies + CSS trim stay co-located
      LEADING_TRIM_TAGS = %w[html body].freeze
      private_constant :LEADING_TRIM_TAGS

      # Packaged YAML language server modeline.
      SCHEMA_MODELINE = '# yaml-language-server: $schema=https://raw.githubusercontent.com/html2rss/html2rss/refs/heads/master/schema/html2rss-config.schema.json'

      # Ordered Segmenter strategies tried until the items selector quality gate passes.
      SEGMENT_STRATEGIES = %i[list cluster semantic].freeze

      # Minimum matched segment/article pairs required to emit an items selector.
      MIN_SELECTOR_MATCHES = 2

      # Request keys {Capture.build} forwards to {Config::AutoSourceRequest}.
      REQUEST_KEYS = %i[items_selector limit local_file_path max_redirects max_requests total_timeout_seconds].freeze
      private_constant :REQUEST_KEYS

      Options = Data.define(:topics, :title, :summary, :force, :enhance)

      ##
      # Capture-only inputs; every member is optional.
      class Options
        # @param topics [Array<String>, nil] directory topics override
        # @param title [String, nil] title override
        # @param summary [String, nil] summary override
        # @param force [Boolean] whether to ignore native feed detection
        # @param enhance [Boolean, nil] +false+ turns enhance off (default on)
        def initialize(topics: nil, title: nil, summary: nil, force: false, enhance: nil)
          super
        end
      end

      CaptureResult = Data.define(
        :config, :yaml, :articles_count, :channel_title, :has_selectors, :segment_strategy,
        :admission_drops, :selected_strategy, :inferred_topics, :native_feed, :suggested_channel_url,
        :candidates
      )

      ##
      # Result of a capture operation (config plus quality meta).
      class CaptureResult
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
        # @param suggested_channel_url [String, nil]
        # @param candidates [Hash{Symbol=>Array}, nil] ranked selector buckets from {SelectorCandidates}
        def initialize(config:, articles_count:, channel_title:, has_selectors:, segment_strategy:, # rubocop:disable Metrics/MethodLength
                       yaml: nil, admission_drops: {}, selected_strategy: nil, inferred_topics: [], native_feed: nil,
                       suggested_channel_url: nil, candidates: nil)
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
            native_feed:,
            suggested_channel_url:,
            candidates: candidates || SelectorCandidates.empty
          )
        end
        # rubocop:enable Metrics/ParameterLists

        ##
        # @return [Boolean] whether first-party RSS was detected
        def native_feed?
          !native_feed.nil?
        end
      end

      class << self
        ##
        # Analyzes a URL and builds a reusable feed config.
        #
        # @param url [String] source page URL
        # @param strategy [Symbol] request strategy (+:auto+, +:default+, +:botasaurus+)
        # @option options [String, nil] :items_selector optional selector hint
        # @option options [Array<String>, nil] :topics optional directory topics override
        # @option options [String, nil] :title optional title override
        # @option options [String, nil] :summary optional summary override
        # @option options [Boolean] :force whether to ignore native feed detection
        # @option options [Boolean, nil] :enhance +false+ turns enhance off (default on)
        # @option options [Integer, nil] :max_redirects optional redirect limit override
        # @option options [Integer, nil] :max_requests optional request budget override
        # @option options [Integer, nil] :total_timeout_seconds optional wall-clock bound (seconds) for the whole
        #   request chain, including every +:auto+ fallback hop (shared budget, not per hop)
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
      # @option options [Integer, nil] :limit max articles to keep
      # @option options [String, nil] :local_file_path optional local HTML file path
      # @option options [Integer, nil] :max_redirects optional redirect limit override
      # @option options [Integer, nil] :max_requests optional request budget override
      # @option options [Integer, nil] :total_timeout_seconds optional wall-clock bound for the request chain
      # @option options [Array<String>, nil] :topics see {Options}
      # @option options [String, nil] :title see {Options}
      # @option options [String, nil] :summary see {Options}
      # @option options [Boolean, nil] :force see {Options}
      # @option options [Boolean, nil] :enhance see {Options}
      def initialize(url, strategy: :auto, **options)
        @strategy = strategy
        @request = Config::AutoSourceRequest.from_shortcut(url, strategy:, **options.slice(*REQUEST_KEYS))
        @options = Options.new(**options.slice(*Options.members))
        @url = url
      end

      ##
      # Runs the capture pipeline.
      #
      # @return [CaptureResult]
      def build # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        outcome = FeedPipeline.new(raw_config).to_outcome
        selectors, segment_strategy, candidates = derive_selectors(outcome.response, outcome.articles)
        ch_title = @options.title || channel_title_from(outcome.response)
        topics = @options.topics || infer_topics("#{@url} #{ch_title}")
        native_feed = probe_native_feed(outcome.response) unless @options.force

        config = {
          directory: build_directory(ch_title, topics),
          channel: build_channel(outcome.response, ch_title),
          selectors: selectors.empty? ? nil : selectors,
          **strategy_stamp(outcome),
          **local_file_request_overlay
        }.compact

        CaptureResult.new(
          config:,
          articles_count: outcome.articles.size,
          channel_title: ch_title,
          has_selectors: !selectors.empty?,
          segment_strategy:,
          admission_drops: outcome.admission_drops,
          selected_strategy: outcome.selected_strategy,
          inferred_topics: topics,
          native_feed:,
          suggested_channel_url: suggested_channel_url(outcome),
          candidates:
        )
      end

      private

      def build_directory(title, topics)
        summary_text = @options.summary || "#{title} updates and announcements."
        {
          topics: topics.take(2),
          title:,
          summary: summary_text[0, 160]
        }.compact
      end

      def probe_native_feed(response)
        Syndication::Discovery.native_feed_url(response:, request_session: discovery_session)&.to_s
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error
        nil
      end

      def discovery_session
        config = Config.from_hash(raw_config)
        resources = FeedPipeline::RuntimePolicy.resources_for(config)
        strategy = FeedPipeline::StrategyPlan.concrete_for_diagnostic(@strategy)
        RequestSession.build(
          config:,
          strategy:,
          budget: resources.budget,
          policy: resources.policy
        )
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
        config = @request.to_config
        config[:strategy] = :local_file if @request.local_file_path
        config
      end

      def local_file_request_overlay
        return {} unless @request.local_file_path

        { strategy: :local_file, request: { local_file_path: @request.local_file_path } }
      end

      # @return [Array(Hash, Symbol, nil, Hash)] selectors, segment strategy, candidate buckets
      def derive_selectors(response, articles)
        return [*hint_selectors, SelectorCandidates.empty] if @request.items_selector
        return [{}, nil, SelectorCandidates.empty] unless response.html_response?
        return [*default_selectors, SelectorCandidates.empty] if articles.empty?

        vocabulary = Vocabulary[Channel.language_for(response)]
        sst = Html::SST::Normalizer.call(response.body, vocabulary:)
        return [*default_selectors, SelectorCandidates.empty] unless sst

        select_enhance_selectors(sst, articles, vocabulary)
      end

      def hint_selectors
        [{ items: { selector: @request.items_selector, enhance: enhance? } }, :hint]
      end

      def default_selectors
        [{ items: { selector: Selectors::DEFAULT_ITEMS_SELECTOR, enhance: enhance? } }, :default]
      end

      def select_enhance_selectors(sst, articles, vocabulary)
        evidence = collect_items_evidence(sst, articles, vocabulary)
        candidates = SelectorCandidates.call(items_evidence: evidence, min_matches: MIN_SELECTOR_MATCHES)
        top = candidates[:items].first
        return [*default_selectors, candidates] unless top

        strategy = evidence.find { |entry| entry[:selector] == top[:selector] }&.fetch(:strategy)
        items = { selector: top[:selector], enhance: top[:enhance] }
        [{ items: }, strategy, candidates]
      end

      def collect_items_evidence(sst, articles, vocabulary)
        link_resolver = AutoSource::Scoring::LinkResolver.new(@url, vocabulary:)
        enhance = enhance?

        SEGMENT_STRATEGIES.flat_map do |strategy|
          segments = AutoSource::Segmenter.call(
            sst, base_url: @url, strategy:, link_resolver:
          )
          matched = match_segments_to_articles(segments, articles)
          next [] if matched.size < MIN_SELECTOR_MATCHES

          items_evidence_for(matched, strategy:, enhance:, vocabulary:)
        end
      end

      def items_evidence_for(matched, strategy:, enhance:, vocabulary:)
        roots = lift_heading_link_roots(matched.map { |pair| pair[:segment].root_node }, vocabulary)
        selector_variants_for(roots).map do |kind, selector|
          { selector:, enhance:, strategy:, kind:, match_count: matched.size, roots: }
        end
      end

      def selector_variants_for(roots)
        [
          [:shared_class, shared_class_items_selector(roots)],
          [:unique_tag, unique_tag_items_selector(roots)],
          [:path, path_items_selector(roots)]
        ].filter_map { |kind, selector| [kind, selector] if selector }
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
        return unless (resolved = Url.resolve_web(segment.primary_link.attrs.href, @url, web_only: false))

        articles_by_url[resolved.to_s] || articles_by_url.values.find { |a| fuzzy_url_match?(a.url, resolved) }
      end

      def fuzzy_url_match?(article_url, resolved)
        article_url.to_s.end_with?(resolved.path.to_s)
      end

      def lift_heading_link_roots(roots, vocabulary)
        enclosed = enclosed_root_counts(roots)
        roots.map { |root| lift_heading_link_root(root, enclosed, vocabulary) }
      end

      def lift_heading_link_root(root, enclosed, vocabulary)
        return root unless heading_or_inner_title_link?(root)

        walk_usable_card(root, Html::SST::Index.for_node!(root), enclosed, vocabulary)
      end

      def walk_usable_card(root, index, enclosed, vocabulary)
        candidate = root
        parent = index.parent_of(root)
        while Html::Navigator.usable_card_parent?(parent, vocabulary:)
          break if contains_other_root?(parent, enclosed)

          candidate = parent
          parent = index.parent_of(parent)
        end
        candidate
      end

      # Identity-keyed tally of how many distinct roots each node is, or strictly encloses, so the
      # card walk answers "does this ancestor hold another root?" without rescanning all roots.
      def enclosed_root_counts(roots)
        tally = Hash.new(0).compare_by_identity
        roots.uniq(&:object_id).each do |root|
          tally[root] += 1
          count_enclosing_ancestors(root, tally)
        end
        tally
      end

      def count_enclosing_ancestors(root, tally)
        index = Html::SST::Index.for_node!(root)
        ancestor = index.parent_of(root)
        while ancestor
          tally[ancestor] += 1
          ancestor = index.parent_of(ancestor)
        end
      end

      def heading_or_inner_title_link?(node)
        name = node.name.to_s
        return false if wrapping_anchor_root?(node)

        Html::Navigator::HEADING_TAGS.include?(name) || name == 'a'
      end

      def wrapping_anchor_root?(node)
        return false unless node.name.to_s == 'a'

        tags = Html::Navigator::WRAPPING_ANCHOR_CHILD_TAGS
        node.find { |child| !child.equal?(node) && tags.include?(child.name.to_s) }
      end

      # The walked-from root is itself tallied under every ancestor, so more than one means another root.
      def contains_other_root?(parent, enclosed)
        enclosed[parent] > 1
      end

      def shared_class_items_selector(roots)
        shared = roots.map { |root| root.attrs.class_names }.reduce { |left, right| left & right }
        return nil if shared.nil? || shared.empty?

        "#{roots.first.name}.#{shared.min}"
      end

      def unique_tag_items_selector(roots)
        names = roots.map { |root| root.name.to_s }.uniq
        names.join(', ') if names.size > 1
      end

      def path_items_selector(roots)
        css_from_trimmed_tag_path(common_path_prefix(roots.map(&:tag_path)))
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

      def common_path_prefix(paths)
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
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error
        nil
      end

      # Captured YAML carries only an items selector, so enhance is its one way to fill title and url.
      def enhance? = @options.enhance != false

      def suggested_channel_url(outcome)
        entry = outcome.scrape_target.entry_url.to_s
        effective = outcome.scrape_target.effective_url.to_s
        return effective unless Url.from_absolute(entry).same_document?(Url.from_absolute(effective))

        final = outcome.response.url.to_s
        return final unless Url.from_absolute(@url).same_document?(Url.from_absolute(final))

        nil
      rescue Html2rss::Url::InvalidUrlError
        nil
      end
    end
  end
end
