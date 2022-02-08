# frozen_string_literal: true

require 'addressable/uri'

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
    # @param url [String]
    # @return [Addressable::URI] sanitized and normalized URL
    def self.sanitize_url(url)
      squished_url = url.to_s.split.join
      return if squished_url.to_s == ''

      Addressable::URI.parse(squished_url).normalize.to_s
    end
  end
end
