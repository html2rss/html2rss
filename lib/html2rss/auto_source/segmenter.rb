# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Discovers candidate content segments from an SST::Document.
    #
    # Strategies:
    # - +:semantic+ — leaf article/section/li/tr/div containers with a primary link
    # - +:list+ — repeated tag_path anchors walked to a shared container boundary
    # - +:cluster+ — class / structure clustering for anchorless card grids
    class Segmenter
      # @param document [SST::Document]
      # @param base_url [String, Html2rss::Url]
      # @param strategy [Symbol]
      # @param permit_unanchored [Boolean]
      # @param minimum_selector_frequency [Integer]
      # @param use_top_selectors [Integer]
      # @return [Array<Segment>]
      def self.call(document, base_url:, strategy:, permit_unanchored: false,
                    minimum_selector_frequency: 2, use_top_selectors: 5)
        new(
          document,
          base_url:,
          strategy:,
          permit_unanchored:,
          minimum_selector_frequency:,
          use_top_selectors:
        ).call
      end

      # rubocop:disable Metrics/ParameterLists
      def initialize(document, base_url:, strategy:, permit_unanchored: false,
                     minimum_selector_frequency: 2, use_top_selectors: 5)
        raise ArgumentError, 'document must be SST::Document' unless document.is_a?(SST::Document)
        raise ArgumentError, "unknown strategy: #{strategy.inspect}" unless Segment::STRATEGIES.include?(strategy)

        @document = document
        @base_url = base_url
        @strategy = strategy
        @permit_unanchored = permit_unanchored
        @minimum_selector_frequency = minimum_selector_frequency
        @use_top_selectors = use_top_selectors
        @link_resolver = Scoring::LinkResolver.new(base_url)
        @noise_policy = Scoring::NoisePolicy.new(link_resolver: @link_resolver, index: document.index)
      end
      # rubocop:enable Metrics/ParameterLists

      # @return [Array<Segment>]
      def call
        case @strategy
        when :semantic then Semantic.call(self)
        when :list then List.call(self)
        when :cluster then Cluster.call(self)
        end
      end

      attr_reader :document, :base_url, :permit_unanchored, :minimum_selector_frequency,
                  :use_top_selectors, :link_resolver, :noise_policy

      # @return [SST::Index]
      def index = document.index
    end
  end
end
