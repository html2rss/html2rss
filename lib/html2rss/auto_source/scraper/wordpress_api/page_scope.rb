# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class WordpressApi
        PageScope = Data.define(:query, :fetchable, :reason)

        ##
        # Determines whether a WordPress page can safely be mapped to a posts query.
        #
        # @!attribute [r] query
        #   @return [Hash{String => String}] query params to apply to the posts request
        # @!attribute [r] fetchable
        #   @return [Boolean] whether a posts follow-up is safe for this page
        # @!attribute [r] reason
        #   @return [Symbol] classification of the resolved page scope
        class PageScope
          # Archive kinds mapped to the posts-endpoint query key that scopes them; the order is the
          # precedence when a page signals several kinds (before date archives).
          ARCHIVE_TAXONOMIES = { 'category' => 'categories', 'tag' => 'tags', 'author' => 'author' }.freeze
          # Canonical path segment for paginated archives.
          PAGE_SEGMENT = 'page'
          # Canonical query key used for paginated archives.
          PAGED_QUERY_KEY = 'paged'

          ##
          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @param url [Html2rss::Url] canonical page URL
          # @return [PageScope] derived page scope
          def self.from(parsed_body:, url:)
            Resolver.new(parsed_body:, url:).call
          end

          ##
          # @param query [Hash{String => String}] scoped query params for the posts endpoint
          # @param fetchable [Boolean] whether a posts follow-up is safe for this page
          # @param reason [Symbol] classification of the resolved page scope
          def initialize(query:, fetchable:, reason:) = super(query: query.freeze, fetchable:, reason:)

          ##
          # @return [Boolean] whether the page may safely use the posts API follow-up
          alias fetchable? fetchable

          ##
          # Resolves the page scope from page markup and canonical URL signals.
          class Resolver # rubocop:disable Metrics/ClassLength
            ##
            # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
            # @param url [Html2rss::Url] canonical page URL
            def initialize(parsed_body:, url:)
              @parsed_body = parsed_body
              @url = Html2rss::Url.from_absolute(url)
            end

            ##
            # @return [PageScope] derived page scope
            def call
              scope = taxonomy_scope ||
                      date_scope ||
                      fallback_scope

              apply_pagination(scope)
            end

            private

            attr_reader :parsed_body, :url

            def taxonomy_scope
              segment, query_key = ARCHIVE_TAXONOMIES.find { |kind, _| taxonomy_archive?(kind) }
              return unless segment

              scoped_scope(query_key => archive_id(segment))
            end

            def date_scope
              return unless date_archive?

              range = DateArchiveRange.from_segments(scoped_path_segments)
              return unknown_archive_scope unless range

              PageScope.new(query: range, fetchable: true, reason: :archive)
            end

            def fallback_scope
              return unknown_archive_scope if archive_like?
              return non_archive_scope if singular_like?

              PageScope.new(query: {}, fetchable: true, reason: :unscoped)
            end

            def apply_pagination(scope)
              page = archive_page_number
              return scope unless scope.fetchable? && page

              scope.with(query: scope.query.merge('page' => page.to_s))
            end

            def scoped_scope(query)
              return unknown_archive_scope if query.values.any?(&:nil?)

              PageScope.new(query:, fetchable: true, reason: :archive)
            end

            def unknown_archive_scope
              PageScope.new(query: {}, fetchable: false, reason: :unsupported_archive)
            end

            def non_archive_scope
              PageScope.new(query: {}, fetchable: false, reason: :non_archive)
            end

            def taxonomy_archive?(segment)
              body_classes.include?(segment) || leading_path_segment == segment
            end

            def date_archive?
              body_classes.include?('date') || date_archive_path?
            end

            def archive_like?
              body_classes.include?('archive')
            end

            def singular_like?
              body_classes.intersect?(%w[page single singular attachment]) ||
                body_classes.any? { _1.match?(/\A(?:page-id|postid)-\d+\z/) }
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
              href = parsed_body.at_css(WordpressApi::CANONICAL_LINK_SELECTOR)&.[]('href').to_s.strip
              return url if href.empty?

              canonical_url = Html2rss::Url.from_relative(href, url)
              same_origin_url?(canonical_url, url) ? canonical_url : url
            rescue Html2rss::Url::InvalidUrlError
              url
            end

            def path_segments
              @path_segments ||= canonical_or_current_url.path_segments
            end

            def scoped_path_segments
              @scoped_path_segments ||= paginated_path? ? path_segments[0...-2] : path_segments
            end

            def leading_path_segment
              scoped_path_segments.first
            end

            def date_archive_path?
              DateArchiveRange.path?(scoped_path_segments)
            end

            def paginated_path?
              return false if path_segments.length < 2
              return false unless path_segments[-2] == PAGE_SEGMENT

              !parse_positive_integer(path_segments[-1]).nil?
            end

            def archive_page_number
              parse_positive_integer(canonical_or_current_url.query_values[PAGED_QUERY_KEY]) || path_page_number
            end

            def path_page_number
              return unless paginated_path?

              parse_positive_integer(path_segments[-1])
            end

            def same_origin_url?(left, right)
              [left.scheme, left.host, left.port] == [right.scheme, right.host, right.port]
            end

            def parse_positive_integer(value)
              return nil unless value.to_s.match?(/\A\d+\z/)

              number = value.to_i
              return nil if number < 1

              number
            end
          end
        end
      end
    end
  end
end
