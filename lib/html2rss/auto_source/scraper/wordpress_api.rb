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
        UNKNOWN_SCOPE = :unknown_scope

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
          @page_scope_query = nil
          @page_scope_query_resolved = false
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

        attr_reader :parsed_body, :url, :request_session

        def fetch_posts
          response = posts_response
          return unless response

          Array(response.parsed_body)
        rescue RequestService::UnsupportedResponseContentType, JSON::ParserError => error
          Log.warn("#{self.class}: failed to parse WordPress API posts (#{error.message})")
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
          return unless (api_root = api_root_url)
          return if page_scope_query == UNKNOWN_SCOPE

          if api_root.query.to_s.include?('rest_route=')
            query_root_posts_url(api_root)
          else
            Html2rss::Url.from_relative(POSTS_PATH, normalized_api_root(api_root)).with_query_values(posts_query)
          end
        end

        def api_root_url
          href = parsed_body.at_css(API_LINK_SELECTOR)&.[]('href').to_s.strip
          return if href.empty?

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
              'rest_route' => "#{route}/wp/v2/posts",
              **posts_query
            )
          )
        end

        def normalized_api_root(api_root)
          normalized = api_root.to_s.sub(%r{/*\z}, '')
          Html2rss::Url.from_absolute("#{normalized}/")
        end

        def posts_query
          {
            '_fields' => POSTS_FIELDS.join(','),
            'per_page' => '100'
          }.merge(page_scope_query || {})
        end

        def page_scope_query
          return @page_scope_query if @page_scope_query_resolved

          @page_scope_query = category_scope_query ||
                              tag_scope_query ||
                              author_scope_query ||
                              date_scope_query ||
                              fallback_scope_query
          @page_scope_query_resolved = true
          @page_scope_query
        end

        def category_scope_query
          return unless body_classes.include?('category')
          return UNKNOWN_SCOPE unless (term_id = archive_id('category'))

          { 'categories' => term_id }
        end

        def tag_scope_query
          return unless body_classes.include?('tag')
          return UNKNOWN_SCOPE unless (term_id = archive_id('tag'))

          { 'tags' => term_id }
        end

        def author_scope_query
          return unless body_classes.include?('author')
          return UNKNOWN_SCOPE unless (author_id = archive_id('author'))

          { 'author' => author_id }
        end

        def date_scope_query
          return unless body_classes.include?('date')

          archive_range = date_archive_range
          return UNKNOWN_SCOPE unless archive_range

          {
            'after' => archive_range.fetch(:after),
            'before' => archive_range.fetch(:before)
          }
        end

        def fallback_scope_query
          return {} unless archive_like_page?

          UNKNOWN_SCOPE
        end

        def archive_like_page?
          %w[archive category tag author date].any? { body_classes.include?(_1) }
        end

        def body_classes
          @body_classes ||= parsed_body.at_css('body')&.[]('class').to_s.split
        end

        def archive_id(prefix)
          body_classes.filter_map do |klass|
            klass[Regexp.new("^#{Regexp.escape(prefix)}-(\\d+)$"), 1]
          end.first
        end

        def canonical_or_current_url
          href = parsed_body.at_css(CANONICAL_LINK_SELECTOR)&.[]('href').to_s.strip
          return url if href.empty?

          Html2rss::Url.from_relative(href, url)
        rescue ArgumentError
          url
        end

        def date_archive_range
          bounds = date_archive_bounds
          return unless bounds

          start_date = bounds.fetch(:start_date)
          end_date = bounds.fetch(:end_date)
          return unless start_date && end_date

          {
            after: iso8601_start(start_date),
            before: iso8601_start(end_date)
          }
        rescue Date::Error
          nil
        end

        def date_archive_bounds
          components = date_archive_components
          return unless components

          start_date = Date.new(*components.fetch(:start_date_parts))
          {
            start_date:,
            end_date: next_archive_boundary(start_date, components.fetch(:precision))
          }
        end

        def date_archive_components
          segments = canonical_or_current_url.path.to_s.split('/').reject(&:empty?)
          return unless segments.first&.match?(/\A\d{4}\z/)

          year = segments.fetch(0).to_i
          month = parse_archive_segment(segments[1], 1, 12)
          day = parse_archive_segment(segments[2], 1, 31)
          precision = archive_precision(month:, day:)

          {
            start_date_parts: [year, month || 1, day || 1],
            precision:
          }
        end

        def next_archive_boundary(start_date, precision)
          {
            year: start_date.next_year,
            month: start_date.next_month,
            day: start_date.next_day
          }.fetch(precision)
        end

        def archive_precision(month:, day:)
          return :day if day
          return :month if month

          :year
        end

        def iso8601_start(date)
          date.strftime('%Y-%m-%dT00:00:00Z')
        end

        def parse_archive_segment(value, minimum, maximum)
          return nil unless value&.match?(/\A\d+\z/)

          number = value.to_i
          return nil if number < minimum || number > maximum

          number
        end

        def normalized_rest_route(route)
          value = route.to_s
          value = '/' if value.empty?
          value = "/#{value}" unless value.start_with?('/')
          value.sub(%r{/+\z}, '')
        end
      end
    end
  end
end
