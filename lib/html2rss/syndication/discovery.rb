# frozen_string_literal: true

module Html2rss
  module Syndication
    ##
    # Finds an RSS/Atom URL for a page via head alternates and same-origin path guesses.
    #
    # Ports configs +probe_rss+ path/alternate logic onto {RequestSession#follow_up}.
    # Head alternates go first, those whose title or URL hints audio ({AUDIO_HINT}) ahead of
    # the rest; they are fetched as +:advertised_feed+ with the page's
    # {RequestService::FeedAdvertisement}, so a feed the page advertises on another host is
    # followed (see {RequestService::Policy}). Path guesses stay same-origin.
    module Discovery
      # Common feed path suffixes probed after head +rel=alternate+ hints.
      DEFAULT_PATHS = CandidateCatalog::FEED_PATHS
      # Word-ish audio hint in an alternate's title or URL (Podlove-style per-format podcast feeds).
      AUDIO_HINT = /(?<![[:alpha:]])(?:podcast|audio|mp3|m4a|aac|opus|episode)s?(?![[:alpha:]])/i

      class << self
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
        # rubocop:disable-next Metrics/ParameterLists -- discovery kwargs stay co-located
        def best_feed_url(page_url:, request_session:, parsed_body: nil, html: nil, extra_paths: [],
                          max_probes: nil)
          best_feed_response(
            page_url:, request_session:, parsed_body:, html:, extra_paths:, max_probes:
          )&.url
        end

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
        # rubocop:disable-next Metrics/ParameterLists, Metrics/MethodLength -- discovery kwargs stay co-located
        def best_feed_response(page_url:, request_session:, parsed_body: nil, html: nil, extra_paths: [],
                               max_probes: nil)
          page = Html2rss::Url.from_absolute(page_url)
          advertisement = advertisement_for(parsed_body, page)
          candidates = candidates(page, advertisement, html:, extra_paths:)
          Log.debug(
            "Syndication::Discovery: host=#{page.host} candidate_count=#{candidates.size}"
          )

          first_feedish_response(
            candidates, request_session:, origin_url: page, advertisement:, max_probes:
          ).tap do |response|
            next unless response

            Log.info({
              event_name: 'syndication.discovery.selected',
              host: page.host,
              message: "Syndication::Discovery: host=#{page.host} selected_feed_url=#{response.url}"
            }.to_json)
          end
        end

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
          candidates(page, advertisement_for(parsed_body, page), html:, extra_paths:)
        end

        ##
        # @param response [Html2rss::RequestService::Response, nil]
        # @return [Boolean]
        def feedish?(response)
          return false unless response
          return false unless successful_status?(response)

          response.feed_response?
        end

        ##
        # Directory-relative feed path guesses for a page URL.
        #
        # @param page_url [String, Html2rss::Url]
        # @return [Array<String>] relative paths
        def page_dir_paths(page_url)
          path = Html2rss::Url.from_absolute(page_url).path
          return [] if path == '/'

          dir = path.sub(%r{/[^/]*$}, '/')
          ["#{dir}feed", "#{dir}rss.xml", "#{dir}atom.xml"]
        end

        private

        def successful_status?(response)
          status = response.status
          status.nil? || status.between?(200, 299)
        end

        def first_feedish_response(urls, request_session:, origin_url:, advertisement:, max_probes: nil)
          scoped = max_probes.nil? ? urls.lazy : urls.lazy.take(max_probes)
          scoped.filter_map do |url|
            response = probe(url, request_session:, origin_url:, advertisement:)
            response if feedish?(response)
          end.first
        end

        def probe(url, request_session:, origin_url:, advertisement:)
          if advertisement.advertises?(url)
            request_session.follow_up(url:, relation: :advertised_feed, origin_url:, advertisement:)
          else
            request_session.follow_up(url:, relation: :auto_source, origin_url:)
          end
        rescue Html2rss::Error => error
          Log.debug("Syndication::Discovery: probe skipped host=#{origin_url.host} (#{error.class})")
          nil
        end

        def candidates(page, advertisement, html:, extra_paths:)
          (alternate_feed_urls(page, advertisement, html:) + path_guess_urls(page, extra_paths:)).uniq
        end

        # An HTML page without a parsed document still gets an (empty) advertisement.
        def advertisement_for(parsed_body, page)
          doc = parsed_body.is_a?(Nokogiri::HTML::Document) ? parsed_body : Nokogiri::HTML::Document.new
          RequestService::FeedAdvertisement.from_document(doc, page_url: page)
        end

        def alternate_feed_urls(page, advertisement, html:)
          feeds = advertisement.feeds
          return AlternateLinks.hrefs(html.to_s).filter_map { |href| absolute_url(page, href) }.uniq if feeds.empty?

          audio, other = feeds.keys.partition { |url| AUDIO_HINT.match?("#{feeds.fetch(url)} #{url}") }
          audio + other
        end

        def path_guess_urls(page, extra_paths:)
          paths = (page_dir_paths(page) + DEFAULT_PATHS + Array(extra_paths)).uniq
          paths.filter_map { |path| absolute_url(page, path) }
        end

        def absolute_url(base, path)
          Html2rss::Url.from_relative(path, base)
        rescue Html2rss::Url::InvalidUrlError
          nil
        end
      end
    end
  end
end
