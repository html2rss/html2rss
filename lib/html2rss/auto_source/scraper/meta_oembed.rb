# frozen_string_literal: true

require 'json'
require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes OpenGraph meta tags and oEmbed JSON descriptors from HTML pages.
      class MetaOembed
        include Enumerable

        # Selector for OpenGraph meta tags.
        OG_META_SELECTOR = 'meta[property^="og:"], meta[property^="article:"], meta[name^="twitter:"]'
        # Selector for oEmbed JSON link tag.
        OEMBED_LINK_SELECTOR = 'link[rel="alternate"][type="application/json+oembed"][href]'

        # Mapping of meta property names to article attribute keys.
        META_MAP = {
          'og:title' => :title,
          'twitter:title' => :title,
          'og:url' => :url,
          'og:description' => :description,
          'twitter:description' => :description,
          'og:image' => :image,
          'twitter:image' => :image,
          'article:published_time' => :published_at,
          'article:author' => :author
        }.freeze
        private_constant :META_MAP

        # @return [Symbol] scraper config key
        def self.options_key = :meta_oembed

        class << self
          # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
          # @return [Boolean] whether OpenGraph tags or oEmbed link exist
          def articles?(parsed_body)
            return false unless parsed_body

            !parsed_body.at_css('meta[property="og:title"]').nil? ||
              !parsed_body.at_css(OEMBED_LINK_SELECTOR).nil?
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base page URL
        # @param request_session [Html2rss::RequestSession, nil] shared request session for follow-up fetches
        # @param _opts [Hash] unused scraper-specific options
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        # @return [void]
        def initialize(parsed_body, url:, request_session: nil, **_opts)
          @parsed_body = parsed_body
          @url = Html2rss::Url.from_absolute(url)
          @request_session = request_session
        end

        ##
        # Yields normalized article hash extracted from OpenGraph meta tags and optional oEmbed data.
        #
        # @yieldparam article [Hash{Symbol => Object}] normalized article hash
        # @return [Enumerator, void] enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?

          article = build_article
          yield article if article
        end

        private

        attr_reader :parsed_body, :url, :request_session

        # @return [Hash{Symbol => Object}, nil] assembled article hash or nil
        def build_article
          meta_data = extract_meta_data
          oembed_data = fetch_oembed_data

          article_url = resolve_url(meta_data[:url]) || url
          title = oembed_data[:title] || meta_data[:title]

          return unless title

          assemble_article(meta_data, oembed_data, article_url, title)
        end

        # @return [Hash{Symbol => Object}] extracted metadata hash
        def extract_meta_data
          {}.tap do |data|
            parsed_body.css(OG_META_SELECTOR).each do |meta|
              prop = meta['property'] || meta['name']
              content = meta['content']
              next if prop.nil? || content.nil? || content.empty?

              assign_meta_prop(data, prop, content)
            end
          end
        end

        # @param data [Hash{Symbol => Object}] target metadata accumulator
        # @param prop [String] meta tag property/name
        # @param content [String] meta tag content
        # @return [void]
        def assign_meta_prop(data, prop, content)
          key = META_MAP[prop]
          data[key] ||= content if key
        end

        # @return [Hash{Symbol => Object}] oEmbed fields hash
        def fetch_oembed_data
          return {} unless request_session && (link_node = parsed_body.at_css(OEMBED_LINK_SELECTOR))
          return {} unless (oembed_url = resolve_url(link_node['href']))

          response = request_session.follow_up(url: oembed_url, relation: :auto_source, origin_url: url)
          parse_oembed_response(response)
        rescue Html2rss::Error, RequestService::UnsupportedResponseContentType, JSON::ParserError => error
          Log.warn("#{self.class}: failed to fetch oEmbed payload (#{error.class}: #{error.message})")
          {}
        end

        # @param response [Html2rss::RequestService::Response, nil] HTTP response
        # @return [Hash{Symbol => Object}] parsed oEmbed fields
        def parse_oembed_response(response)
          return {} unless response

          payload = response.parsed_body
          return {} unless payload.is_a?(Hash)

          thumbnail = payload['thumbnail_url'] || (payload['type'] == 'photo' ? payload['url'] : nil)

          { title: payload['title'], author: payload['author_name'], thumbnail:, html: payload['html'] }.compact
        end

        # @param meta_data [Hash{Symbol => Object}] extracted OpenGraph meta tags
        # @param oembed_data [Hash{Symbol => Object}] parsed oEmbed fields
        # @param article_url [Html2rss::Url] resolved article URL
        # @param title [String] resolved article title
        # @return [Hash{Symbol => Object}] final article hash
        def assemble_article(meta_data, oembed_data, article_url, title)
          {
            url: article_url,
            title:,
            description: meta_data[:description] || oembed_data[:html],
            author: oembed_data[:author] || meta_data[:author],
            published_at: meta_data[:published_at],
            image: oembed_data[:thumbnail] || meta_data[:image]
          }.compact
        end

        # @param raw_url [String, nil] raw relative or absolute URL string
        # @return [Html2rss::Url, nil] resolved absolute URL or nil
        def resolve_url(raw_url)
          return if raw_url.nil? || raw_url.empty?

          Html2rss::Url.from_relative(raw_url, url)
        rescue Html2rss::Url::InvalidUrlError
          nil
        end
      end
    end
  end
end
