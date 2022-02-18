# frozen_string_literal: true

require 'addressable/uri'
require 'faraday'
require 'faraday_middleware'
require 'json'
require 'regexp_parser'
require 'tzinfo'

module Html2rss
  ##
  # The collecting tank for utility methods.
  module Utils
    ##
    # @param url [String, URI]
    # @param base_url [String]
    # @return [Addressable::URI]
    def self.build_absolute_url_from_relative(url, base_url)
      url = Addressable::URI.parse(url) if url.is_a?(String)

      return url if url.absolute?

      Addressable::URI.parse(base_url).tap do |uri|
        path = url.path
        fragment = url.fragment

        uri.path = path.to_s.start_with?('/') ? path : "/#{path}"
        uri.query = url.query
        uri.fragment = fragment if fragment
      end
    end

    OBJECT_TO_XML_TAGS = {
      array: ['<array>', '</array>'],
      object: ['<object>', '</object>']
    }.freeze

    ##
    # A naive implementation of "Object to XML".
    #
    # @param object [#each_pair, #each]
    # @return [String] representing the object in XML, with all types being Strings
    def self.object_to_xml(object)
      if object.respond_to? :each_pair
        prefix, suffix = OBJECT_TO_XML_TAGS[:object]
        xml = object.each_pair.map { |k, v| "<#{k}>#{object_to_xml(v)}</#{k}>" }
      elsif object.respond_to? :each
        prefix, suffix = OBJECT_TO_XML_TAGS[:array]
        xml = object.map { |o| object_to_xml(o) }
      else
        xml = [object]
      end

      "#{prefix}#{xml.join}#{suffix}"
    end

    ##
    # Removes any space, parses and normalizes the given url.
    # @param url [String]
    # @return [Addressable::URI] sanitized and normalized URL
    def self.sanitize_url(url)
      squished_url = url.to_s.split.join
      return if squished_url.to_s == ''

      Addressable::URI.parse(squished_url).normalize.to_s
    end

    ##
    # Allows override of time zone locally inside supplied block; resets previous time zone when done.
    #
    # @param time_zone [String]
    # @return whatever the given block returns
    def self.use_zone(time_zone)
      raise ArgumentError, 'a block is required' unless block_given?

      time_zone = TZInfo::Timezone.get(time_zone)

      prev_tz = ENV['TZ']
      ENV['TZ'] = time_zone.name
      yield
    ensure
      ENV['TZ'] = prev_tz if prev_tz
    end

    ##
    # Builds a titleized representation of the URL.
    # @param url [#to_s]
    # @return [String]
    def self.titleized_url(url)
      uri = Addressable::URI.parse(url.to_s)
      host = uri.host

      nicer_path = uri.path.split('/').reject { |part| part == '' }
      nicer_path.any? ? "#{host}: #{nicer_path.map(&:capitalize).join(' ')}" : host
    end

    ##
    # @param url [String, URI::HTTPS, URI::HTTP, Addressable::URI]
    # @param convert_json_to_xml [true, false] Should JSON be converted to XML
    # @param headers [Hash] additional HTTP request headers to use for the request
    # @return [String]
    def self.request_body_from_url(url, convert_json_to_xml: false, headers: {})
      body = Faraday.new(url: url, headers: headers) do |faraday|
        faraday.use FaradayMiddleware::FollowRedirects
        faraday.adapter Faraday.default_adapter
      end.get.body

      convert_json_to_xml ? object_to_xml(JSON.parse(body)) : body
    end

    ##
    # Parses the given String and builds a Regexp out of it.
    #
    # It will remove one pair of sourrounding slashes ('/') from the String
    # to maintain backwards compatibility before building the Regexp.
    #
    # @param string [String]
    # @return [Regexp]
    def self.build_regexp_from_string(string)
      raise ArgumentError, 'must be a string!' unless string.is_a?(String)

      string = string[1..-2] if string[0] == '/' && string[-1] == '/'

      Regexp::Parser.parse(string, options: ::Regexp::EXTENDED | ::Regexp::IGNORECASE).to_re
    end
  end
end
