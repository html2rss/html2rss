# frozen_string_literal: true

require 'addressable/uri'
require 'cgi'
require 'ipaddr'
require 'nokogiri'

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
  # rubocop:disable-next Metrics/ClassLength -- value object owns resolve/sanitize/titleize/identity
  class Url
    include Comparable

    # Closed set of query params that carry campaign or referrer data, never page identity.
    TRACKING_PARAM = /\A(?:utm_.*|fbclid|gclid|msclkid|mc_cid|mc_eid|ref|ref_src)\z/i

    NO_PARAMS = [].freeze
    private_constant :NO_PARAMS

    # Raised when a string cannot be parsed or resolved to a valid URL.
    class InvalidUrlError < Html2rss::Error
      # @return [Symbol]
      def kind = :invalid_url
    end

    # Regular expression for basic URI format validation
    URI_REGEXP = Addressable::URI::URIREGEX
    # Schemes accepted by channel URL validation.
    SUPPORTED_SCHEMES = %w[http https].to_set.freeze
    SCHEME_PREFIX = /\A([a-z][a-z0-9+.-]*):/i
    private_constant :SCHEME_PREFIX

    ##
    # Creates a URL from a relative path and base URL.
    #
    # @param relative_url [String, Html2rss::Url] the relative URL to resolve
    # @param base_url [String, Html2rss::Url] the base URL to resolve against
    # @return [Url] the resolved, normalized absolute URL
    # @raise [InvalidUrlError] if the URL cannot be parsed
    def self.from_relative(relative_url, base_url)
      url = parse(relative_url.to_s.strip, base_url.to_s[SCHEME_PREFIX, 1])
      return new(url.normalize) if url.absolute?

      join_parsed_base(base_url, url)
    rescue Addressable::URI::InvalidURIError
      raise InvalidUrlError, 'URL could not be parsed'
    end

    # @param base_url [String, Url]
    # @param url [Addressable::URI]
    # @return [Url]
    def self.join_parsed_base(base_url, url)
      uri = Addressable::URI.parse(base_url.to_s)
      new(uri.join(url).normalize)
    end
    private_class_method :join_parsed_base

    ##
    # The one parse entry. Like browsers (WHATWG URL), a backslash before the query or fragment of an
    # http(s) URL is a path separator: +files\a.pdf+ is +files/a.pdf+ and +https:\\example.com\x+ is
    # +https://example.com/x+. A backslash ends the authority, so +https://example.com\@host.example/+
    # keeps +example.com+ as host. Query and fragment, and non-http(s) URLs, are left untouched.
    #
    # @param text [String] raw URL or reference
    # @param base_scheme [String, nil] scheme a scheme-less +text+ resolves against
    # @return [Addressable::URI]
    # @raise [Addressable::URI::InvalidURIError]
    def self.parse(text, base_scheme = nil)
      scheme = text[SCHEME_PREFIX, 1] || base_scheme
      return Addressable::URI.parse(text) unless SUPPORTED_SCHEMES.include?(scheme&.downcase)

      head, separator, tail = text.partition(/[?#]/)
      Addressable::URI.parse("#{head.tr('\\', '/')}#{separator}#{tail}")
    end
    private_class_method :parse

    ##
    # Creates a URL by sanitizing a raw URL string.
    # Removes spaces and extracts the first valid URL from the string.
    #
    # @param raw_url [String] the raw URL string to sanitize
    # @return [Url, nil] the sanitized URL, or nil if no valid URL found
    def self.sanitize(raw_url)
      match = raw_url.to_s.match(%r{(?:https?:[/\\]{2}|ftp://|mailto:)[^\s<>"]+})
      return unless match

      new(parse(match[0]).normalize)
    end

    ##
    # Creates a URL from an already-absolute URL string.
    #
    # @param url_string [String, Html2rss::Url] the absolute URL to parse
    # @return [Url] the parsed and normalized URL
    # @raise [InvalidUrlError] if the URL is not absolute or cannot be parsed
    def self.from_absolute(url_string)
      return url_string if url_string.is_a?(self)

      new(parse(url_string.to_s.lstrip).normalize).tap do |url|
        raise InvalidUrlError, 'URL must be absolute' unless url.absolute?
      end
    rescue Addressable::URI::InvalidURIError
      raise InvalidUrlError, 'URL must be absolute'
    end

    ##
    # Creates a URL for channel use with validation.
    # Validates that the URL meets channel requirements (absolute, no @, supported schemes).
    #
    # @param url_string [String] the URL string to validate and parse
    # @return [Url] the validated and parsed URL
    # @raise [InvalidUrlError] if the URL doesn't meet channel requirements
    # @example Creating a channel URL
    #   Url.for_channel('https://example.com')
    #   # => #<Html2rss::Url:... @uri=#<Addressable::URI:... URI:https://example.com>>
    # @example Invalid channel URL
    #   Url.for_channel('/relative/path')
    #   # => raises InvalidUrlError: "URL must be absolute"
    def self.for_channel(url_string)
      stripped = url_string.to_s.lstrip
      return nil if stripped.empty?

      from_absolute(stripped).tap { validate_channel_url(_1) }
    end

    ##
    # Creates an absolute http(s) URL, for example for a channel image.
    #
    # @param url_string [String, Html2rss::Url] the URL to validate and parse
    # @return [Url] the validated and parsed URL
    # @raise [InvalidUrlError] if the URL is not absolute or not http(s)
    def self.from_absolute_web(url_string)
      from_absolute(url_string).tap { validate_scheme(_1) }
    end

    ##
    # The one resolver for a declared web reference (a media file, an item link, a player +src+, an
    # advertised feed): +ref+ resolved against +base_url+ when relative, kept only when http(s) ({#web?}).
    # A +javascript:+, +data:+, +ftp:+ or +mailto:+ reference, or a relative one without a base, names none.
    #
    # @param ref [String, Html2rss::Url, nil] an absolute or relative URL, possibly padded with whitespace
    # @param base_url [String, Html2rss::Url, nil] the document the reference appears in
    # @return [Url, nil] the absolute http(s) URL, or nil when +ref+ is blank, unparseable or not http(s)
    def self.resolve_web(ref, base_url = nil)
      return unless ref.to_s.match?(/\S/)

      url = from_relative(ref, base_url)
      url if url.web?
    rescue InvalidUrlError
      nil
    end

    ##
    # Extracts a base URL from HTML metadata tags.
    #
    # @param html [String] raw HTML content
    # @return [Url, nil] the extracted absolute URL, or nil if none is found
    def self.extract_from_html(html)
      doc = Nokogiri::HTML(html)
      tags = { 'link[rel="canonical"]' => 'href', 'meta[property="og:url"]' => 'content',
               'meta[name="twitter:url"]' => 'content', 'base[href]' => 'href' }
      tags.each do |sel, attr|
        val = doc.at_css(sel)&.[](attr)
        return from_absolute(val)
      rescue InvalidUrlError
        nil
      end
      nil
    end

    ##
    # Validates that a URL meets channel requirements.
    #
    # @param url [Url] the URL to validate
    # @raise [InvalidUrlError] if the URL doesn't meet channel requirements
    def self.validate_channel_url(url)
      has_forbidden_at = url.user
      has_forbidden_at ||= [url.query, url.fragment].compact.any? { |value| value.include?('@') }
      raise InvalidUrlError, 'URL must not contain an @ character' if has_forbidden_at

      validate_scheme(url)
    end

    def self.validate_scheme(url)
      raise InvalidUrlError, "URL scheme '#{url.scheme}' is not supported" unless url.web?
    end

    private_class_method :validate_channel_url, :validate_scheme

    ##
    # The wrapped URI stays unfrozen and private: freezing makes Addressable recompute every
    # normalized part that +normalize+ just produced. Mutating operations dup first.
    #
    # @param uri [Addressable::URI] the normalized Addressable::URI (internal use only)
    def initialize(uri)
      @uri = uri
      @path_segments = path.split('/').reject(&:empty?).freeze
      freeze
    end

    # @return [String] normalized URL string
    def to_s = @uri.to_str

    # @return [String, nil] URI scheme, for example `http` or `https`
    def scheme = @uri.scheme

    # @return [String, nil] URI host component
    def host = @uri.host

    # @return [String, nil] userinfo user, without the password
    def user = @uri.user

    # Registrable domain (eTLD+1). Same-site hosts like www.example.com and news.example.com
    # share `example.com`. IP literals stay the host so 1.2.3.4 is not treated as `3.4`.
    #
    # @return [String, nil]
    def domain
      return host if ip_address_host?

      @uri.domain || host
    end

    # @return [Integer, nil] URI port component
    def port = @uri.port

    # @return [String, nil] URI path component
    def path = @uri.path

    # @return [String, nil] URI query string without leading `?`
    def query = @uri.query

    # @return [String, nil] URI fragment without leading `#`
    def fragment = @uri.fragment

    # @return [Boolean] whether the URL includes scheme and host
    def absolute? = @uri.absolute?

    # @return [Boolean] whether the URL is an absolute http(s) URL ({SUPPORTED_SCHEMES}), the only kind a feed
    #   ships as a link, enclosure or player source
    def web? = SUPPORTED_SCHEMES.include?(scheme)

    ##
    # Returns the URL query string as a hash of string keys and values.
    #
    # @return [Hash{String => String}] normalized query parameters
    def query_values = @uri.query_values || {}

    ##
    # Returns the URL path split into non-empty segments.
    #
    # @return [Array<String>] normalized path segments
    attr_reader :path_segments

    ##
    # Returns a copy of the URL with the provided path.
    #
    # @param path [String] normalized absolute path
    # @return [Url] a new URL with the updated path
    def with_path(path)
      uri = @uri.dup
      uri.path = path
      self.class.from_absolute(uri)
    end

    ##
    # Returns a copy of the URL with the fragment removed (dedup / self-link identity).
    #
    # @return [Url] this URL when already fragment-free; otherwise a new URL
    def without_fragment
      fragment ? self.class.from_absolute(@uri.omit(:fragment)) : self
    end

    ##
    # Returns a copy of the URL with {TRACKING_PARAM} query params removed; the remaining
    # params keep their order.
    #
    # @return [Url] this URL when it carries no tracking param; otherwise a new URL
    def without_tracking_params
      return self if query_params.none? { tracking_param?(_1) }

      uri = @uri.dup
      uri.query = query_params.reject { tracking_param?(_1) }.join('&')
      self.class.from_absolute(uri)
    end

    ##
    # Returns a copy of the URL with the provided scheme.
    #
    # @param scheme [String] for example +https+
    # @return [Url] a new URL with the updated scheme
    def with_scheme(scheme)
      uri = @uri.dup
      uri.scheme = scheme
      self.class.from_absolute(uri)
    end

    ##
    # Returns a copy of the URL with the provided query values.
    #
    # @param values [Hash{String, Symbol => #to_s}] query parameters to assign
    # @return [Url] a new URL with the updated query string
    def with_query_values(values)
      uri = @uri.dup
      uri.query_values = values.transform_keys(&:to_s).transform_values(&:to_s)
      self.class.from_absolute(uri)
    end

    ##
    # Returns a titleized representation of the URL path.
    # Converts the path to a human-readable title by cleaning and capitalizing words.
    # Removes file extensions and special characters, then capitalizes each word.
    #
    # @return [String] the titleized path, or empty string if path is empty
    # @example Basic titleization
    #   url = Url.from_absolute('https://example.com/foo-bar/baz.txt')
    #   url.titleized # => "Foo Bar Baz"
    # @example With URL encoding
    #   url = Url.from_absolute('https://example.com/hello%20world/article.html')
    #   url.titleized # => "Hello World Article"
    def titleized
      nicer_path = CGI.unescapeURIComponent(path).gsub(/[^a-zA-Z0-9.]/, ' ').split
      nicer_path.map!(&:capitalize)
      File.basename(nicer_path.join(' '), '.*')
    end

    ##
    # Returns a titleized representation of the URL with prefixed host.
    # Creates a channel title by combining host and path information.
    # Useful for RSS channel titles that need to identify the source.
    #
    # @return [String] the titleized channel URL
    # @example With path
    #   url = Url.from_absolute('https://example.com/foo-bar/baz')
    #   url.channel_titleized # => "example.com: Foo Bar Baz"
    # @example Without path (root URL)
    #   url = Url.from_absolute('https://example.com')
    #   url.channel_titleized # => "example.com"
    def channel_titleized
      nicer_path = CGI.unescapeURIComponent(path).split('/').reject(&:empty?)

      nicer_path.any? ? "#{host}: #{nicer_path.map(&:capitalize).join(' ')}" : host
    end

    ##
    # Compares this URL with another URL for equality.
    # URLs are considered equal if their string representations are the same.
    #
    # @param other [Url] the other URL to compare with
    # @return [Integer] -1, 0, or 1 for less than, equal, or greater than
    def <=>(other) = to_s <=> other.to_s

    ##
    # Returns true if this URL is equal to another URL.
    #
    # @param other [Object] the other object to compare with
    # @return [Boolean] true if the URLs are equal
    def ==(other) = other.is_a?(Url) && to_s == other.to_s
    alias eql? ==

    ##
    # Whether +other+ names the same document (trailing slash and fragment ignored).
    # Differs from {#==}: `/blog` and `/blog/` match; query strings must still match.
    #
    # @param other [Object]
    # @return [Boolean]
    def same_document?(other)
      return false unless other.is_a?(Url)

      document_identity == other.document_identity
    end

    ##
    # Returns the hash code for this URL.
    #
    # @return [Integer] the hash code
    def hash = to_s.hash

    ##
    # Returns a string representation of the URL for debugging.
    #
    # @return [String] the debug representation
    def inspect = "#<#{self.class}:#{object_id} @uri=#{@uri.inspect}>"

    ##
    # Resolves +relative_uri+ against this URL's already-parsed Addressable URI.
    #
    # @param relative_uri [Addressable::URI]
    # @return [Url]
    def join_uri(relative_uri)
      self.class.new(@uri.join(relative_uri).normalize)
    end

    ##
    # "Same article" key: host, port, slash-stripped path, and the sorted query params minus
    # {TRACKING_PARAM}. Scheme, fragment, trailing slash, tracking params, and param order are
    # ignored, so +http://example.com/a+ and +https://example.com/a/?utm_source=x#top+ share it;
    # every other query param stays significant. Keys page placement, self-link rejection, and
    # feed-item dedupe, unlike {#same_document?}, which stays scheme- and query-exact.
    #
    # @return [Array] equal for URLs naming the same article
    def article_identity = [host, port, path.chomp('/'), article_params]

    protected

    # Same-document key: scheme, authority, slash-stripped path, and query (fragment omitted).
    # Two URLs share it exactly when {#same_document?} holds.
    #
    # @return [String]
    def document_identity
      "#{scheme}\0#{@uri.authority}\0#{path.chomp('/')}\0#{query}"
    end

    private

    # @return [Array<String>] raw +key=value+ query pairs, in source order
    def query_params = query ? query.split('&') : NO_PARAMS

    # @return [Array<String>] sorted non-tracking query pairs; the shared empty list without a query
    def article_params = query ? query_params.reject { tracking_param?(_1) }.sort : NO_PARAMS

    def tracking_param?(pair) = TRACKING_PARAM.match?(pair.partition('=').first)

    def ip_address_host?
      !IPAddr.new(host).nil?
    rescue IPAddr::Error
      false
    end
  end
end
