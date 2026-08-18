# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class RequestService
    ##
    # To be used by strategies to provide their response.
    class Response
      # Default when a strategy does not attach transport telemetry.
      EMPTY_TRANSPORT_META = {}.freeze
      # Default when a strategy does not capture sub-resource responses.
      EMPTY_CAPTURED_RESPONSES = [].freeze

      # Bodies that look like HTML even when Content-Type is missing, empty, or wrong.
      HTML_BODY_SNIFF = /\A\s*(?:<!DOCTYPE\s+html|<html)/i

      ##
      # @param body [String] the body of the response
      # @param url [Html2rss::Url] the final request URL
      # @param headers [Hash] the headers of the response
      # @param status [Integer, nil] the HTTP status code when available
      # @param transport_meta [Hash] allowlisted upstream telemetry (frozen when present)
      # @param captured_responses [Array<Hash>] JSON XHR/fetch bodies captured during browser scrapes
      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists -- transport + capture fields stay co-located
      def initialize(body:, url:, headers: {}, status: nil, transport_meta: EMPTY_TRANSPORT_META,
                     captured_responses: EMPTY_CAPTURED_RESPONSES)
        @body = body

        headers = headers.dup
        headers.transform_keys!(&:to_s)
        HashUtil.assert_string_keys!(headers, context: 'response headers', deep: false)

        @headers = headers
        @status = status
        @url = url
        @transport_meta = transport_meta.nil? || transport_meta.empty? ? EMPTY_TRANSPORT_META : transport_meta.freeze
        @captured_responses = if captured_responses.nil? || captured_responses.empty?
                                EMPTY_CAPTURED_RESPONSES
                              else
                                captured_responses.freeze
                              end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      # @return [String] the raw body of the response
      attr_reader :body

      # @return [Hash{String => Object}] the headers of the response
      attr_reader :headers

      # @return [Integer, nil] the HTTP status code when known
      attr_reader :status

      # @return [Html2rss::Url] the URL of the response
      attr_reader :url

      # @return [Hash] allowlisted upstream transport telemetry
      attr_reader :transport_meta

      # @return [Array<Hash>] captured JSON XHR/fetch responses (empty when unsupported)
      attr_reader :captured_responses

      # @return [String] normalized content type header value
      def content_type = header('content-type').to_s

      # @return [Boolean] whether response content is JSON
      def json_response? = content_type.include?('application/json')

      # @return [Boolean] whether response content is HTML
      def html_response? = content_type.include?('text/html')

      ##
      # @return [Nokogiri::HTML::Document, Hash] the parsed body of the response, frozen object
      # @raise [UnsupportedResponseContentType] if the content type is not supported
      def parsed_body
        @parsed_body ||= if html_document?
                           parse_html_document
                         elsif json_response?
                           JSON.parse(body, symbolize_names: true).freeze
                         else
                           raise UnsupportedResponseContentType, "Unsupported content type: #{content_type}"
                         end
      end

      private

      # @param name [String] canonical header name
      # @return [Object, nil] header value when present
      def header(name)
        headers.fetch(name) do
          headers.find { |key, _value| key.casecmp?(name) }&.last
        end
      end

      def parse_html_document
        Nokogiri::HTML(body).tap do |doc|
          doc.xpath('//comment()').each(&:remove)
        end.freeze
      end

      def html_document?
        html_response? || (!json_response? && html_looking_body?)
      end

      def html_looking_body?
        body.to_s.match?(HTML_BODY_SNIFF)
      end
    end
  end
end
