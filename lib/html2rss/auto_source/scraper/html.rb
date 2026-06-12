# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes article-like blocks from plain HTML by looking for repeated link
      # structures when richer structured data is unavailable.
      #
      # The approach is intentionally heuristic:
      # 1. collect repeated anchor paths
      # 2. walk upward to a shared container shape
      # 3. extract the best anchor found inside each container
      #
      # This scraper is broader and noisier than `SemanticHtml`, so it acts as a
      # fallback for pages without stronger semantic signals.
      class Html
        include Enumerable

        # Absolute base URL used when probe-time detection needs to normalize relative hrefs.
        DETECTION_BASE_URL = 'https://example.com'
        # Minimum selector frequency required to treat a path as a stable list signal.
        DEFAULT_MINIMUM_SELECTOR_FREQUENCY = 2
        # Number of most frequent selectors kept for container extraction.
        DEFAULT_USE_TOP_SELECTORS = 5

        ##
        # @return [Symbol] config key used to enable or configure this scraper
        def self.options_key = :html

        ##
        # Probes whether the document appears to contain repeated anchor
        # structures that this fallback scraper can cluster into article-like
        # containers.
        #
        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @return [Boolean] true when the scraper can likely extract articles
        def self.articles?(parsed_body)
          new(parsed_body, url: DETECTION_BASE_URL).any?
        end

        ##
        # Simplify an XPath selector by removing the index notation.
        # This keeps repeated anchor paths comparable across sibling blocks.
        #
        # @param xpath [String] original XPath
        # @return [String] XPath without positional indexes
        def self.simplify_xpath(xpath)
          HtmlExtractor::ListCandidates.simplify_xpath(xpath)
        end

        # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
        # @param url [String] The base URL.
        # @param extractor [Class] The extractor class to handle article extraction.
        # @param opts [Hash] Additional options.
        # @option opts [Integer] :minimum_selector_frequency minimum count before a selector is considered stable
        # @option opts [Integer] :use_top_selectors number of top selectors to keep
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
          @opts = opts
          @link_heuristics = LinkHeuristics.new(url)
        end

        attr_reader :parsed_body

        ##
        # @yieldparam [Hash] The scraped article hash
        # @return [Enumerator] Enumerator for the scraped articles
        def each
          return enum_for(:each) unless block_given?

          each_article_tag do |article_tag, selected_anchor|
            article_hash = extract_article(article_tag, selected_anchor:)
            yield article_hash if article_hash
          end
        end

        ##
        # Decides whether a traversed node has reached a useful article-like
        # boundary for the generic HTML scraper.
        #
        # The predicate prefers containers that add surrounding link context,
        # which helps the scraper move from a leaf anchor toward a repeated
        # teaser/card wrapper.
        #
        # @param node [Nokogiri::XML::Node] candidate boundary node
        # @return [Boolean] true when the node is a good extraction boundary
        def article_tag_condition?(node)
          # Ignore tags that are below ignored DOM chrome.
          return false if HtmlExtractor.ignored_container_path?(node)
          return true if %w[body html].include?(node.name)
          return false unless (parent = node.parent)

          anchor_count(parent) > anchor_count(node)
        end

        private

        ##
        # @return [Integer]
        def minimum_selector_frequency = @opts[:minimum_selector_frequency] || DEFAULT_MINIMUM_SELECTOR_FREQUENCY

        ##
        # @return [Boolean]
        def use_top_selectors = @opts[:use_top_selectors] || DEFAULT_USE_TOP_SELECTORS

        ##
        # @param node [Nokogiri::XML::Node]
        # @return [Integer]
        def anchor_count(node)
          (@anchor_counts ||= {}.compare_by_identity)[node] ||= node.name == 'a' ? 1 : node.css('a').size
        end

        ##
        # @param node [Nokogiri::XML::Node]
        # @return [Boolean]
        def relevant_anchor?(node)
          destination_facts = @link_heuristics.destination_facts(node)
          return false unless destination_facts

          !noise_anchor?(node, destination_facts)
        end

        ##
        # @yield [article_tag, selected_anchor]
        # @yieldparam article_tag [Nokogiri::XML::Node]
        # @yieldparam selected_anchor [Nokogiri::XML::Node]
        # @return [Enumerator, nil]
        def each_article_tag(&block)
          return enum_for(:each_article_tag) unless block

          anchor_filter = ->(node) { relevant_anchor?(node) }
          boundary_condition = ->(node) { article_tag_condition?(node) }

          list_candidates.each_article_tag(anchor_filter:, boundary_condition:, &block)
        end

        ##
        # @param article_tag [Nokogiri::XML::Node]
        # @param selected_anchor [Nokogiri::XML::Node, nil]
        # @return [Hash, nil]
        def extract_article(article_tag, selected_anchor: nil)
          selected_anchor ||= preferred_anchor_for(article_tag)
          return unless selected_anchor
          return if noise_anchor?(selected_anchor, @link_heuristics.destination_facts(selected_anchor))

          @extractor.new(article_tag, base_url: @url, selected_anchor:).call
        end

        ##
        # @param anchor [Nokogiri::XML::Node]
        # @param destination_facts [DestinationFacts]
        # @return [Boolean]
        def noise_anchor?(anchor, destination_facts) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          return true unless destination_facts

          (@noise_anchors ||= {}.compare_by_identity)[anchor] ||= begin
            text = HtmlExtractor.extract_visible_text(anchor).to_s.strip

            destination_facts.taxonomy_path ||
              short_utility_label?(text, destination_facts) ||
              (@link_heuristics.recommended_text?(text) && destination_facts.shallow) ||
              (@link_heuristics.utility_prefix_text?(text) && destination_facts.high_confidence_utility_destination) ||
              (@link_heuristics.utility_text?(text) && destination_facts.vanity_path)
          end
        end

        ##
        # @param text [String]
        # @param destination_facts [DestinationFacts]
        # @return [Boolean]
        def short_utility_label?(text, destination_facts)
          destination_facts.utility_path &&
            !destination_facts.content_path &&
            !destination_facts.strong_post_suffix &&
            text.scan(/\p{Alnum}+/).size <= 3
        end

        ##
        # @param article_tag [Nokogiri::XML::Node]
        # @return [Nokogiri::XML::Node, nil]
        def preferred_anchor_for(article_tag)
          article_tag.css(HtmlExtractor::MAIN_ANCHOR_SELECTOR).find { relevant_anchor?(_1) } ||
            HtmlExtractor.main_anchor_for(article_tag)
        end

        ##
        # @return [HtmlExtractor::ListCandidates]
        def list_candidates
          HtmlExtractor::ListCandidates.new(
            parsed_body,
            minimum_selector_frequency:,
            use_top_selectors:
          )
        end
      end
    end
  end
end
