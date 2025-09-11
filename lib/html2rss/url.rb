# frozen_string_literal: true

require 'addressable/uri'
require 'cgi'

module Html2rss
  ##
  # A value object representing a resolved, absolute URL with built-in operations.
  # Provides URL resolution, sanitization, and titleization capabilities.
  #
  # @example Creating a URL from a relative path
  #   url = Url.from_relative('/path/to/article', 'https://example.com')
  #   url.to_s # => "https://example.com/path/to/article"
  #
  # @example Sanitizing a raw URL string
  #   url = Url.sanitize('https://example.com/  ')
  #   url.to_s # => "https://example.com/"
  #
  # @example Getting titleized versions
  #   url = Url.from_relative('/foo-bar/baz.txt', 'https://example.com')
  #   url.titleized # => "Foo Bar Baz"
  #   url.channel_titleized # => "example.com: Foo Bar Baz"
  class Url
    include Comparable

    ##
    # Creates a URL from a relative path and base URL.
    #
    # @param relative_url [String, Html2rss::Url] the relative URL to resolve
    # @param base_url [String, Html2rss::Url] the base URL to resolve against
    # @return [Url] the resolved absolute URL
    # @raise [ArgumentError] if the URL cannot be parsed
    def self.from_relative(relative_url, base_url)
      url = Addressable::URI.parse(relative_url.to_s.strip)
      return new(url) if url.absolute?

      base_uri = Addressable::URI.parse(base_url.to_s)
      base_uri.path = '/' if base_uri.path.empty?

      new(base_uri.join(url).normalize)
    end

    ##
    # Creates a URL by sanitizing a raw URL string.
    # Removes spaces and extracts the first valid URL from the string.
    #
    # @param raw_url [String] the raw URL string to sanitize
    # @return [Url, nil] the sanitized URL, or nil if no valid URL found
    def self.sanitize(raw_url)
      matched_urls = raw_url.to_s.scan(%r{(?:(?:https?|ftp|mailto)://|mailto:)[^\s<>"]+})
      url = matched_urls.first.to_s.strip
      return nil if url.empty?

      new(Addressable::URI.parse(url).normalize)
    end

    ##
    # @param uri [Addressable::URI] the underlying Addressable::URI object (internal use only)
    def initialize(uri)
      @uri = uri.freeze
      freeze
    end

    # Delegate common URI operations to the underlying URI
    def to_s = @uri.to_s
    def scheme = @uri.scheme
    def host = @uri.host
    def path = @uri.path
    def query = @uri.query
    def fragment = @uri.fragment
    def absolute? = @uri.absolute?

    ##
    # Returns a titleized representation of the URL path.
    # Converts the path to a human-readable title by cleaning and capitalizing words.
    #
    # @return [String] the titleized path, or empty string if path is empty
    # @example
    #   url = Url.from_relative('/foo-bar/baz.txt', 'https://example.com')
    #   url.titleized # => "Foo Bar Baz"
    def titleized
      return '' if @uri.path.empty?

      nicer_path = CGI.unescapeURIComponent(@uri.path)
                      .split('/')
                      .flat_map do |part|
        part.gsub(/[^a-zA-Z0-9\.]/, ' ').gsub(/\s+/, ' ').split
      end

      nicer_path.map!(&:capitalize)
      File.basename(nicer_path.join(' '), '.*')
    end

    ##
    # Returns a titleized representation of the URL with prefixed host.
    # Creates a channel title by combining host and path information.
    #
    # @return [String] the titleized channel URL
    # @example
    #   url = Url.from_relative('/foo-bar/baz', 'https://example.com')
    #   url.channel_titleized # => "example.com: Foo Bar Baz"
    def channel_titleized
      nicer_path = CGI.unescapeURIComponent(@uri.path).split('/').reject(&:empty?)
      host = @uri.host

      nicer_path.any? ? "#{host}: #{nicer_path.map(&:capitalize).join(' ')}" : host
    end

    ##
    # Compares this URL with another URL for equality.
    # URLs are considered equal if their string representations are the same.
    #
    # @param other [Url] the other URL to compare with
    # @return [Integer] -1, 0, or 1 for less than, equal, or greater than
    def <=>(other)
      to_s <=> other.to_s
    end

    ##
    # Returns true if this URL is equal to another URL.
    #
    # @param other [Object] the other object to compare with
    # @return [Boolean] true if the URLs are equal
    def ==(other)
      other.is_a?(Url) && to_s == other.to_s
    end

    ##
    # Returns the hash code for this URL.
    #
    # @return [Integer] the hash code
    def hash
      to_s.hash
    end

    ##
    # Returns a string representation of the URL for debugging.
    #
    # @return [String] the debug representation
    def inspect
      "#<#{self.class}:#{object_id} @uri=#{@uri.inspect}>"
    end
  end
end
