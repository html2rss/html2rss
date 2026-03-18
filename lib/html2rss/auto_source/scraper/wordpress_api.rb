# frozen_string_literal: true

require 'date'
require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      # Scrapes WordPress sites through their REST API instead of parsing article HTML.
      class WordpressApi # rubocop:disable Metrics/ClassLength
        include Enumerable

        API_LINK_SELECTOR = 'link[rel="https://api.w.org/"][href]'
        CANONICAL_LINK_SELECTOR = 'link[rel="canonical"][href]'
        POSTS_FIELDS = %w[id title excerpt content link date categories].freeze
        POSTS_PATH = 'wp/v2/posts'

        def self.options_key = :wordpress_api

        ##
        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
        # @return [Boolean] whether the page advertises a WordPress REST API endpoint
        def self.articles?(parsed_body)
          return false unless parsed_body

          !parsed_body.at_css(API_LINK_SELECTOR).nil?
        end

        ##
        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] canonical page URL
        # @param request_session [Html2rss::RequestSession, nil] shared request session for follow-up fetches
        # @param _opts [Hash] unused scraper-specific options
        # @return [void]
        def initialize(parsed_body, url:, request_session: nil, **_opts)
          @parsed_body = parsed_body
          @url = Html2rss::Url.from_absolute(url)
          @request_session = request_session
          @page_scope = PageScope.from(parsed_body:, url: @url)
        end

        ##
        # Yields article hashes from the WordPress posts API.
        #
        # @yieldparam article [Hash<Symbol, Object>] normalized article hash
        # @return [Enumerator, void] enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?
          return unless (posts = fetch_posts)

          posts.filter_map { article_from(_1) }.each { yield(_1) }
        end

        private

        attr_reader :parsed_body, :url, :request_session, :page_scope

        def fetch_posts
          response = posts_response
          return unless response

          Array(response.parsed_body)
        rescue RequestService::UnsupportedResponseContentType => error
          Log.warn("#{self.class}: unsupported WordPress API posts content type (#{error.message})")
          nil
        rescue JSON::ParserError => error
          Log.warn("#{self.class}: failed to parse WordPress API posts JSON (#{error.message})")
          nil
        end

        def posts_response
          return unless request_session
          return unless (resolved_posts_url = posts_url)

          request_session.follow_up(
            url: resolved_posts_url,
            relation: :auto_source,
            origin_url: url
          )
        rescue StandardError => error
          Log.warn("#{self.class}: failed to fetch WordPress API posts (#{error.message})")
          nil
        end

        def posts_url
          api_root = api_root_url
          return unless api_root
          return unless fetchable_page_scope?

          if api_root.query.to_s.include?('rest_route=')
            query_root_posts_url(api_root)
          else
            posts_collection_url(api_root)
          end
        end

        def api_root_url
          href = parsed_body.at_css(API_LINK_SELECTOR)&.[]('href').to_s.strip
          return log_missing_api_root if href.empty?

          Html2rss::Url.from_relative(href, url)
        rescue ArgumentError => error
          Log.warn("#{self.class}: invalid WordPress API endpoint #{href.inspect} (#{error.message})")
          nil
        end

        def article_from(post)
          return unless post.is_a?(Hash)

          article_url = article_url(post)
          return unless article_url

          article_attributes(post, article_url).compact
        end

        def article_url(post)
          absolute_link(post[:link])
        end

        def article_id(_post, article_url)
          string(article_url.path) || string(article_url.query) || article_url.to_s
        end

        def article_title(post)
          rendered_text(post.dig(:title, :rendered))
        end

        def article_description(post)
          rendered_html(post.dig(:content, :rendered)) || rendered_html(post.dig(:excerpt, :rendered))
        end

        def article_published_at(post)
          string(post[:date])
        end

        def article_categories(post)
          Array(post[:categories]).filter_map { |value| string(value) }
        end

        def article_attributes(post, article_url)
          {
            id: article_id(post, article_url),
            title: article_title(post),
            description: article_description(post),
            url: article_url,
            published_at: article_published_at(post),
            categories: article_categories(post)
          }
        end

        def absolute_link(link)
          value = string(link)
          return unless value

          Html2rss::Url.from_relative(value, url)
        rescue ArgumentError
          nil
        end

        def rendered_text(value)
          rendered_html(value)&.then { Nokogiri::HTML.fragment(_1).text.strip }
        end

        def rendered_html(value)
          text = string(value)
          text unless text.nil?
        end

        def string(value)
          text = value.to_s.strip
          text unless text.empty?
        end

        def query_root_posts_url(api_root)
          query = api_root.query_values
          route = normalized_rest_route(query.fetch('rest_route', '/'))
          api_root.with_query_values(
            query.merge(
              'rest_route' => append_posts_route(route),
              **posts_query
            )
          )
        end

        def posts_collection_url(api_root)
          Html2rss::Url.from_relative(POSTS_PATH, normalized_api_root(api_root))
                       .with_query_values(api_root.query_values.merge(posts_query))
        end

        def normalized_api_root(api_root)
          api_root.with_path(normalized_api_path(api_root.path))
        end

        def fetchable_page_scope?
          return true if page_scope.fetchable?

          Log.warn("#{self.class}: unable to derive safe WordPress archive scope for #{url}")
          false
        end

        def log_missing_api_root
          Log.debug("#{self.class}: page advertised WordPress API support without a usable API root")
          nil
        end

        def normalized_api_path(path)
          segments = path.to_s.split('/').reject(&:empty?)
          normalized_path = "/#{segments.join('/')}"
          normalized_path = '/' if normalized_path == '/'
          normalized_path.end_with?('/') ? normalized_path : "#{normalized_path}/"
        end

        def posts_query
          {
            '_fields' => POSTS_FIELDS.join(','),
            'per_page' => '100'
          }.merge(page_scope.query)
        end

        def normalized_rest_route(route)
          value = route.to_s
          value = '/' if value.empty?
          value = "/#{value}" unless value.start_with?('/')
          trim_trailing_slashes(value)
        end

        def trim_trailing_slashes(value)
          end_index = value.length
          end_index -= 1 while end_index > 1 && value.getbyte(end_index - 1) == 47
          value[0, end_index]
        end

        def append_posts_route(route)
          return '/wp/v2/posts' if route == '/'

          "#{route}/wp/v2/posts"
        end
      end
    end
  end
end
