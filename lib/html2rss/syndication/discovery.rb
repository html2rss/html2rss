# frozen_string_literal: true

module Html2rss
  module Syndication
    ##
    # Finds a same-origin RSS/Atom URL for a page via head alternates and path guesses.
    #
    # Ports configs +probe_rss+ path/alternate logic onto {RequestSession#follow_up}.
    module Discovery # rubocop:disable Metrics/ModuleLength -- discovery + path probes stay co-located
      # Common feed path suffixes probed after head +rel=alternate+ hints.
      DEFAULT_PATHS = CandidateCatalog::FEED_PATHS

      LINK_TAG_RE = /<link\b[^>]*>/i
      HREF_RE = /\bhref\s*=\s*["']([^"']+)["']/i
      TYPE_RE = /\btype\s*=\s*["']([^"']+)["']/i
      REL_RE = /\brel\s*=\s*["']([^"']+)["']/i
      private_constant :LINK_TAG_RE, :HREF_RE, :TYPE_RE, :REL_RE

      module_function

      ##
      # Probes candidates lazily and returns the first feedish URL.
      #
      # @param page_url [String, Html2rss::Url] page or origin URL
      # @param request_session [Html2rss::RequestSession] shared session for follow-ups
      # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML when available
      # @param html [String, nil] raw HTML when a document is unavailable
      # @param extra_paths [Array<String>] additional path guesses
      # @param max_probes [Integer, nil] max candidate GETs (nil = uncapped)
      # @return [Html2rss::Url, nil]
      # rubocop:disable Metrics/ParameterLists -- discovery kwargs stay co-located
      def best_feed_url(page_url:, request_session:, parsed_body: nil, html: nil, extra_paths: [],
                        max_probes: nil)
        best_feed_response(
          page_url:, request_session:, parsed_body:, html:, extra_paths:, max_probes:
        )&.url
      end
      # rubocop:enable Metrics/ParameterLists

      ##
      # Like {#best_feed_url} but returns the validated syndication response for parsing.
      #
      # @param page_url [String, Html2rss::Url]
      # @param request_session [Html2rss::RequestSession]
      # @param parsed_body [Nokogiri::HTML::Document, nil]
      # @param html [String, nil]
      # @param extra_paths [Array<String>]
      # @param max_probes [Integer, nil] max candidate GETs (nil = uncapped)
      # @return [Html2rss::RequestService::Response, nil]
      # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- discovery kwargs stay co-located
      def best_feed_response(page_url:, request_session:, parsed_body: nil, html: nil, extra_paths: [],
                             max_probes: nil)
        page = Html2rss::Url.from_absolute(page_url)
        candidates = candidate_urls(page_url: page, parsed_body:, html:, extra_paths:)
        Log.debug(
          "Syndication::Discovery: host=#{page.host} candidate_count=#{candidates.size}"
        )

        first_feedish_response(
          candidates, request_session:, origin_url: page, max_probes:
        ).tap do |response|
          next unless response

          Log.info("Syndication::Discovery: host=#{page.host} selected_feed_url=#{response.url}")
        end
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

      ##
      # Ordered candidate feed URLs (head alternates first, then path guesses).
      #
      # @param page_url [String, Html2rss::Url]
      # @param parsed_body [Nokogiri::HTML::Document, nil]
      # @param html [String, nil]
      # @param extra_paths [Array<String>]
      # @return [Array<Html2rss::Url>]
      def candidate_urls(page_url:, parsed_body: nil, html: nil, extra_paths: [])
        page = Html2rss::Url.from_absolute(page_url)
        (alternate_feed_urls(page, parsed_body:, html:) +
          path_guess_urls(page, extra_paths:)).uniq
      end

      ##
      # @param response [Html2rss::RequestService::Response, nil]
      # @return [Boolean]
      def feedish?(response)
        return false unless response
        return false unless successful_status?(response)

        response.feed_response?
      end

      def successful_status?(response)
        status = response.status
        status.nil? || status.between?(200, 299)
      end
      module_function :successful_status?
      private_class_method :successful_status?

      ##
      # Directory-relative feed path guesses for a page URL.
      #
      # @param page_url [String, Html2rss::Url]
      # @return [Array<String>] relative paths
      def page_dir_paths(page_url)
        path = Html2rss::Url.from_absolute(page_url).path
        return [] if path.nil? || path.empty? || path == '/'

        dir = path.sub(%r{/[^/]*$}, '/')
        ["#{dir}feed", "#{dir}rss.xml", "#{dir}atom.xml"]
      end

      def first_feedish_response(urls, request_session:, origin_url:, max_probes: nil)
        scoped = max_probes.nil? ? urls.lazy : urls.lazy.take(max_probes)
        scoped.filter_map do |url|
          response = probe(url, request_session:, origin_url:)
          response if feedish?(response)
        end.first
      end
      module_function :first_feedish_response
      private_class_method :first_feedish_response

      def first_feedish_url(urls, request_session:, origin_url:, max_probes: nil)
        first_feedish_response(urls, request_session:, origin_url:, max_probes:)&.url
      end
      module_function :first_feedish_url
      private_class_method :first_feedish_url

      def probe(url, request_session:, origin_url:)
        request_session.follow_up(url:, relation: :auto_source, origin_url:)
      rescue Html2rss::Error => error
        Log.debug(
          "Syndication::Discovery: probe skipped host=#{origin_url.host} " \
          "(#{error.class})"
        )
        nil
      end
      module_function :probe
      private_class_method :probe

      def alternate_feed_urls(page, parsed_body:, html:)
        from_document = feed_links_from_document(parsed_body, page)
        return from_document if from_document.any?

        alternate_feed_hrefs(html.to_s, page)
      end
      module_function :alternate_feed_urls
      private_class_method :alternate_feed_urls

      def feed_links_from_document(parsed_body, page)
        return [] unless parsed_body.is_a?(Nokogiri::HTML::Document)

        Html::FeedLink.from_document(parsed_body).filter_map do |link|
          absolute_url(page, link.href)
        end
      end
      module_function :feed_links_from_document
      private_class_method :feed_links_from_document

      def path_guess_urls(page, extra_paths:)
        paths = (page_dir_paths(page) + DEFAULT_PATHS + Array(extra_paths)).uniq
        paths.filter_map { |path| absolute_url(page, path) }
      end
      module_function :path_guess_urls
      private_class_method :path_guess_urls

      def alternate_feed_hrefs(html, page)
        return [] if html.nil? || html.empty?

        html.scan(LINK_TAG_RE).filter_map { |tag| href_from_alternate_link(tag, page) }.uniq
      end
      module_function :alternate_feed_hrefs
      private_class_method :alternate_feed_hrefs

      def href_from_alternate_link(tag, page)
        return unless alternate_rel?(tag)

        href = tag[HREF_RE, 1]
        return if href.nil? || href.empty?
        return unless syndication_type?(tag[TYPE_RE, 1]) || feed_like_href?(href)

        absolute_url(page, href.strip)
      end
      module_function :href_from_alternate_link
      private_class_method :href_from_alternate_link

      def alternate_rel?(tag)
        tag[REL_RE, 1].to_s.downcase.split(/\s+/).include?('alternate')
      end
      module_function :alternate_rel?
      private_class_method :alternate_rel?

      def syndication_type?(type)
        return false if type.nil? || type.empty?

        t = type.downcase
        t.include?('rss+xml') || t.include?('atom+xml') || t.include?('rss') || t.include?('atom')
      end
      module_function :syndication_type?
      private_class_method :syndication_type?

      def feed_like_href?(href)
        href.match?(/rss|atom|feed|\.xml/i)
      end
      module_function :feed_like_href?
      private_class_method :feed_like_href?

      def absolute_url(base, path)
        Html2rss::Url.from_relative(path, base)
      rescue ArgumentError
        nil
      end
      module_function :absolute_url
      private_class_method :absolute_url
    end
  end
end
