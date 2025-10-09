# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Detects RSS, Atom, and JSON feeds in HTML link tags and creates articles for them.
      # This scraper is used as a fallback when no other scrapers can find articles.
      #
      # Features:
      # - Detects RSS, Atom, and JSON feeds via <link rel="alternate"> tags
      # - Creates helpful articles with clickable links to discovered feeds
      # - Uses monthly rotating GUIDs to keep articles visible in feed readers
      # - Includes security measures to prevent XSS attacks
      # - Optimized for performance with cached operations
      #
      # @example HTML that will be detected
      #   <link rel="alternate" type="application/rss+xml" href="/feed.xml" title="RSS Feed">
      #   <link rel="alternate" type="application/atom+xml" href="/atom.xml" title="Atom Feed">
      #   <link rel="alternate" type="application/json" href="/feed.json" title="JSON Feed">
      class RssFeedDetector
        include Enumerable

        # CSS selector for detecting feed link tags
        FEED_LINK_SELECTOR = 'link[rel="alternate"][type*="application/"]'

        # Default categories for all feed articles
        DEFAULT_CATEGORIES = %w[feed auto-detected].freeze

        # Feed type detection patterns
        FEED_TYPE_PATTERNS = {
          json: /\.json$/,
          atom: /atom/,
          rss: // # default fallback
        }.freeze

        def self.options_key = :rss_feed_detector

        ##
        # Check if the parsed_body contains RSS feed link tags.
        # This scraper should only be used as a fallback when other scrapers fail.
        # @param parsed_body [Object] The parsed HTML document
        # @return [Boolean] True if RSS feeds are found, otherwise false.
        def self.articles?(parsed_body)
          return false unless parsed_body

          parsed_body.css(FEED_LINK_SELECTOR).any?
        end

        # @param parsed_body [Object] The parsed HTML document.
        # @param url [String, Html2rss::Url] The base URL.
        # @param opts [Hash] Additional options (unused but kept for consistency).
        def initialize(parsed_body, url:, **opts)
          @parsed_body = parsed_body
          @url = url.is_a?(Html2rss::Url) ? url : Html2rss::Url.from_relative(url.to_s, url.to_s)
          @opts = opts
        end

        attr_reader :parsed_body

        ##
        # Yields article hashes for each discovered RSS feed.
        # @yieldparam [Hash] The RSS feed article hash.
        # @return [Enumerator] Enumerator for the discovered RSS feeds.
        def each
          return enum_for(:each) unless block_given?

          @timestamp = Time.now
          @current_month = @timestamp.strftime('%Y-%m')
          @site_name = extract_site_name

          @parsed_body.css(FEED_LINK_SELECTOR).each do |link|
            feed_url = link['href']
            next if feed_url.nil? || feed_url.empty?

            article_hash = create_article_hash(link, feed_url)
            yield article_hash if article_hash
          end
        end

        private

        def create_article_hash(link, feed_url)
          absolute_url = Html2rss::Url.from_relative(feed_url, @url)
          feed_title = link['title']&.strip
          feed_type = detect_feed_type(feed_url)

          build_article_hash(absolute_url, feed_title, feed_type)
        rescue StandardError => error
          Log.warn "RssFeedDetector: Failed to create article for feed URL '#{feed_url}': #{error.message}"
          nil
        end

        def build_article_hash(absolute_url, feed_title, feed_type)
          {
            title: feed_title || "Subscribe to #{feed_type} Feed",
            url: absolute_url,
            description: create_description(absolute_url, feed_type, feed_title),
            id: generate_monthly_id(absolute_url),
            published_at: @timestamp,
            categories: create_categories(feed_type),
            author: @site_name,
            scraper: self.class
          }
        end

        def generate_monthly_id(absolute_url)
          # Generate a GUID that changes monthly to ensure articles appear as "unread"
          # This makes the gem a good internet citizen by periodically reminding users
          # about available RSS feeds
          "rss-feed-#{absolute_url.hash.abs}-#{@current_month}"
        end

        def detect_feed_type(feed_url)
          url_lower = feed_url.downcase

          case url_lower
          when FEED_TYPE_PATTERNS[:json] then 'JSON Feed'
          when FEED_TYPE_PATTERNS[:atom] then 'Atom'
          else 'RSS'
          end
        end

        def create_description(absolute_url, feed_type, feed_title)
          safe_url = absolute_url.to_s

          html_content = if feed_title
                           "This website has a #{feed_type} feed available: <a href=\"#{safe_url}\">#{feed_title}</a>"
                         else
                           "This website has a #{feed_type} feed available at <a href=\"#{safe_url}\">#{safe_url}</a>"
                         end

          # Sanitize HTML to allow safe HTML while preventing XSS
          sanitize_html(html_content)
        end

        def sanitize_html(html_content)
          # Use the same sanitization as the rest of the project
          context = { config: { channel: { url: @url } } }
          Html2rss::Selectors::PostProcessors::SanitizeHtml.new(html_content, context).get
        end

        def create_categories(feed_type)
          categories = DEFAULT_CATEGORIES.dup
          categories << feed_type.downcase.tr(' ', '-')
          categories
        end

        def extract_site_name
          # Try to extract site name from the HTML title first
          title = @parsed_body.at_css('title')&.text&.strip
          return title if title && !title.empty?

          # Fallback to URL using Html2rss::Url#channel_titleized
          @url.channel_titleized
        end
      end
    end
  end
end
