# frozen_string_literal: true

require 'set' # rubocop:disable Lint/RedundantRequireStatement

module Html2rss
  class AutoSource
    # :nodoc:
    class Paginator
      def initialize(initial_response, pagination_config:, default_config:, request_strategy:, request_headers:)
        @initial_response = initial_response
        @pagination_config = pagination_config || {}
        @default_config = default_config
        @request_strategy = request_strategy
        @request_headers = request_headers
      end

      def responses
        return [initial_response] unless paginate?

        paginate_responses
      end

      private

      attr_reader :initial_response, :pagination_config, :default_config, :request_strategy, :request_headers

      def paginate_responses
        pages = [initial_response]
        visited = Set.new([normalized_url_string(initial_response.url)])
        queue = initial_queue(visited)

        process_next_candidate(queue, pages, visited) while continue_pagination?(pages, queue)

        pages
      end

      def initial_queue(visited)
        filter_candidates(pagination_candidates(initial_response), visited)
      end

      def continue_pagination?(pages, queue)
        pages.size < max_pages && queue.any?
      end

      def process_next_candidate(queue, pages, visited)
        next_url = queue.shift
        normalized_next_url = normalized_url_string(next_url)
        return if visited.include?(normalized_next_url)

        next_response = fetch_page(next_url)
        return unless next_response

        pages << next_response
        visited.add(normalized_next_url)
        queue.replace(merge_candidates(queue, new_candidates(next_response, visited)))
      end

      def new_candidates(page_response, visited)
        filter_candidates(pagination_candidates(page_response), visited)
      end

      def fetch_page(candidate_url)
        RequestService.execute(
          RequestService::Context.new(url: candidate_url, headers: request_headers),
          strategy: request_strategy
        )
      rescue StandardError => error
        Log.warn "Pagination request failed for #{candidate_url}: #{error.message}"
        nil
      end

      def pagination_candidates(page_response)
        return [] unless page_response&.html_response?

        selectors.each_with_object([]) do |selector, urls|
          page_response.parsed_body.css(selector).each do |node|
            next unless (candidate = build_candidate_url(node['href'], page_response.url))

            urls << candidate
          end
        end
      end

      def selectors
        Array(pagination_config[:selectors] || default_config[:selectors])
          .map { |selector| selector.to_s.strip }
          .reject(&:empty?)
      end

      def build_candidate_url(href, base_url)
        sanitized = href&.strip
        return nil if sanitized.nil? || sanitized.empty?
        return nil if sanitized.start_with?('javascript:', '#')

        candidate = Html2rss::Url.from_relative(sanitized, base_url)
        return nil if candidate.to_s == base_url.to_s

        candidate
      rescue Addressable::URI::InvalidURIError, ArgumentError
        nil
      end

      def merge_candidates(existing, additional)
        (existing + additional).uniq(&:to_s)
      end

      def filter_candidates(candidates, visited)
        candidates.reject { |candidate| visited.include?(normalized_url_string(candidate)) }.uniq(&:to_s)
      end

      def normalized_url_string(url)
        url.to_s.delete_suffix('/')
      end

      def enabled?
        pagination_config.fetch(:enabled, true)
      end

      def max_pages
        pagination_config[:max_pages] || default_config[:max_pages]
      end

      def paginate?
        enabled? && max_pages > 1
      end
    end
  end
end
