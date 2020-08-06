require 'active_support/core_ext/hash'
require 'addressable/uri'
require 'builder'
require 'json'
require 'nokogiri'

module Html2rss
  ##
  # The collecting tank for utility methods.
  module Utils
    def self.build_absolute_url_from_relative(url, base_url)
      url = URI(url) if url.is_a?(String)

      return url if url.absolute?

      URI(base_url).tap do |uri|
        uri.path = url.path.to_s.start_with?('/') ? url.path : "/#{url.path}"
        uri.query = url.query
        uri.fragment = url.fragment if url.fragment
      end
    end

    def self.object_to_xml(object)
      object.to_xml(skip_instruct: true, skip_types: true)
    end

    def self.class_from_name(snake_cased_name, module_name)
      camel_cased_name = snake_cased_name.split('_').map(&:capitalize).join
      class_name = ['Html2rss', module_name, camel_cased_name].join('::')
      Object.const_get(class_name)
    end

    def self.sanitize_url(url)
      squished_url = url.to_s.split(' ').join
      return if squished_url.to_s == ''

      Addressable::URI.parse(squished_url).normalize.to_s
    end
  end
end
