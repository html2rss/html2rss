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
      # @param opts [Hash] segmentation options
      # @option opts [Boolean] :permit_unanchored keep containers without a primary link
      # @option opts [Integer] :minimum_selector_frequency list strategy frequency floor
      # @option opts [Integer] :use_top_selectors list strategy selector budget
      # @return [Array<Segment>]
      # rubocop:disable Style/ArgumentsForwarding -- keep named opts for YARD @option
      def self.call(document, base_url:, strategy:, **opts)
        new(document, base_url:, strategy:, **opts).call
      end
      # rubocop:enable Style/ArgumentsForwarding

      # @param document [SST::Document]
      # @param base_url [String, Html2rss::Url]
      # @param strategy [Symbol]
      # @param opts [Hash] segmentation options
      # @option opts [Boolean] :permit_unanchored keep containers without a primary link
      # @option opts [Integer] :minimum_selector_frequency list strategy frequency floor
      # @option opts [Integer] :use_top_selectors list strategy selector budget
      def initialize(document, base_url:, strategy:, **opts)
        raise ArgumentError, 'document must be SST::Document' unless document.is_a?(SST::Document)
        raise ArgumentError, "unknown strategy: #{strategy.inspect}" unless Segment::STRATEGIES.include?(strategy)

        @document = document
        @base_url = base_url
        @strategy = strategy
        @permit_unanchored = opts.fetch(:permit_unanchored, false)
        @minimum_selector_frequency = opts.fetch(:minimum_selector_frequency, 2)
        @use_top_selectors = opts.fetch(:use_top_selectors, 5)
        @link_resolver = Scoring::LinkResolver.new(base_url)
        @noise_policy = Scoring::NoisePolicy.new(link_resolver: @link_resolver, index: document.index)
      end

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
