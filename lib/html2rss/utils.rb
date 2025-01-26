# frozen_string_literal: true

require 'addressable/uri'
require 'regexp_parser'
require 'tzinfo'

module Html2rss
  ##
  # The collecting tank for utility methods.
  module Utils
    ##
    # @param url [String, Addressable::URI]
    # @param base_url [String, Addressable::URI]
    # @return [Addressable::URI]
    def self.build_absolute_url_from_relative(url, base_url)
      url = Addressable::URI.parse(url.to_s.strip)
      return url if url.absolute?

      base_uri = Addressable::URI.parse(base_url)
      base_uri.path = '/' if base_uri.path.empty?

      base_uri.join(url).normalize
    end

    ##
    # Removes any space, parses and normalizes the given url.
    # @param url [String]
    # @return [Addressable::URI, nil] normalized URL, or nil if input is empty
    def self.sanitize_url(url)
      matched_urls = url.to_s.scan(%r{(?:(?:https?|ftp|mailto)://|mailto:)[^\s<>"]+})
      url = matched_urls.first.to_s.strip

      Addressable::URI.parse(url).normalize unless url.empty?
    end

    ##
    # Allows override of time zone locally inside supplied block; resets previous time zone when done.
    #
    # @param time_zone [String]
    # @param default_time_zone [String]
    # @yield block to execute with the given time zone
    # @return [Object] whatever the given block returns
    def self.use_zone(time_zone, default_time_zone: Time.now.getlocal.zone)
      raise ArgumentError, 'a block is required' unless block_given?

      time_zone = TZInfo::Timezone.get(time_zone)

      prev_tz = ENV.fetch('TZ', default_time_zone)
      ENV['TZ'] = time_zone.name
      yield
    ensure
      ENV['TZ'] = prev_tz if prev_tz
    end

    ##
    # Builds a titleized representation of the URL with prefixed host.
    # @param url [Addressable::URI]
    # @return [String]
    def self.titleized_channel_url(url)
      nicer_path = CGI.unescapeURIComponent(url.path).split('/').reject(&:empty?)
      host = url.host

      nicer_path.any? ? "#{host}: #{nicer_path.map(&:capitalize).join(' ')}" : host
    end

    ##
    # Builds a titleized representation of the URL.
    # @param url [Addressable::URI]
    # @return [String]
    def self.titleized_url(url)
      return '' if url.path.empty?

      nicer_path = CGI.unescapeURIComponent(url.path)
                      .split('/')
                      .flat_map do |part|
        part.gsub(/[^a-zA-Z0-9\.]/, ' ').gsub(/\s+/, ' ').split
      end

      nicer_path.map!(&:capitalize)
      File.basename nicer_path.join(' '), '.*'
    end

    ##
    # Parses the given String and builds a Regexp out of it.
    #
    # It will remove one pair of surrounding slashes ('/') from the String
    # to maintain backwards compatibility before building the Regexp.
    #
    # @param string [String]
    # @return [Regexp]
    def self.build_regexp_from_string(string)
      raise ArgumentError, 'must be a string!' unless string.is_a?(String)

      string = string[1..-2] if string.start_with?('/') && string.end_with?('/')
      Regexp::Parser.parse(string, options: ::Regexp::EXTENDED | ::Regexp::IGNORECASE).to_re
    end
  end
end
