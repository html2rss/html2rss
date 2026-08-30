# frozen_string_literal: true

require 'public_suffix'
require 'uri'

module Html2rss
  module MCP
    ##
    # Generates a feed configuration formatted for the curated catalog
    # and discovers native syndication feeds.
    module CatalogConfig
      # Default fallback topic for catalog configs when none are supplied.
      DEFAULT_TOPICS = ['news'].freeze

      # Value object representing the result of catalog config generation.
      CatalogResult = Data.define(
        :yaml, :domain, :native_feed_detected, :alternate_feeds, :articles_count, :suggested_topics
      ) do
        ##
        # @return [Hash{Symbol => Object}]
        def to_h
          {
            yaml:,
            domain:,
            native_feed_detected:,
            alternate_feeds:,
            articles_count:,
            suggested_topics:
          }
        end
      end

      module_function

      ##
      # Generates a catalog-ready feed configuration from a URL.
      #
      # @param url [String] source page URL
      # @param strategy [Symbol, String] request strategy (+:auto+, +:faraday+, +:botasaurus+)
      # @param topics [Array<String>, nil] optional directory topics
      # @param title [String, nil] optional explicit title
      # @param summary [String, nil] optional directory summary (max 160 chars)
      # @return [CatalogResult]
      def generate(url:, strategy: :auto, topics: nil, title: nil, summary: nil) # rubocop:disable Metrics/MethodLength
        validate_topics!(topics) if topics
        domain = extract_domain(url)
        recon = Inspect.call(url:, strategy:)
        alternate_feeds = Array(recon[:alternate_feeds])
        native_feed_detected = alternate_feeds.any?

        capture_result = Capture.build(url, strategy:)
        effective_topics = topics || DEFAULT_TOPICS
        config = assemble_config(capture_result, domain:, title:, summary:, topics: effective_topics)

        CatalogResult.new(
          yaml: Config.to_yaml(config),
          domain:,
          native_feed_detected:,
          alternate_feeds:,
          articles_count: capture_result.articles_count,
          suggested_topics: effective_topics
        )
      end

      ##
      # @param topics [Array<String>]
      # @raise [ArgumentError] if any topic is not in {Config::Validator::DIRECTORY_TOPICS}
      def validate_topics!(topics)
        allowed = Config::Validator::DIRECTORY_TOPICS
        invalid = Array(topics).reject { |topic| allowed.include?(topic.to_s) }
        return if invalid.empty?

        raise ArgumentError, "Invalid topic(s): #{invalid.join(', ')}. Allowed topics: #{allowed.join(', ')}"
      end
      module_function :validate_topics!
      private_class_method :validate_topics!

      ##
      # @param url [String]
      # @return [String] registrable domain or hostname
      def extract_domain(url)
        host = URI.parse(url).host.to_s
        PublicSuffix.domain(host) || host
      rescue StandardError
        URI.parse(url).host.to_s
      end
      module_function :extract_domain
      private_class_method :extract_domain

      ##
      # @param capture_result [Html2rss::Capture::CaptureResult]
      # @param domain [String]
      # @param title [String, nil]
      # @param summary [String, nil]
      # @param topics [Array<String>]
      # @return [Hash]
      def assemble_config(capture_result, domain:, title:, summary:, topics:)
        extracted_title = title || capture_result.channel_title || domain
        directory = { title: extracted_title, summary:, topics: }.compact
        config = { directory:, **capture_result.config }
        config[:channel] ||= {}
        config[:channel][:title] = extracted_title if title || config[:channel][:title].nil?
        config
      end
      module_function :assemble_config
      private_class_method :assemble_config
    end
  end
end
