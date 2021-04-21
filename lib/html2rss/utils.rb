# frozen_string_literal: true

require 'active_support/core_ext/hash'
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

    ##
    # @param object [Array, Hash]
    # @return [String] a string representing the object in XML
    def self.object_to_xml(object)
      object.to_xml(skip_instruct: true, skip_types: true)
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
