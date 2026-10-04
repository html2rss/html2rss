# frozen_string_literal: true

require 'zlib'

module Html2rss
  ##
  # Article is a simple data object representing an article extracted from a page.
  #
  # Description and enclosure wire presentation live in {FeedBuilder::ItemPresentation}.
  class Article
    # Allowed article attributes accepted by the value object constructor.
    PROVIDED_KEYS = %i[id title description url image author guid published_at enclosures categories scraper].freeze
    # Separator used to build deterministic deduplication fingerprints.
    DEDUP_FINGERPRINT_SEPARATOR = '#!/'
    # Sentinel object used to pre-initialize instance variables in the constructor.
    # This ensures all Article instances share the exact same object shape (Ruby 3.3+ optimization),
    # preventing performance warnings and slower instance variable access due to shape transitions
    # when attributes are lazily/conditionally accessed in different sequences.
    NOT_SET = Object.new.freeze

    # @param id [String, nil] stable article identifier
    # @param title [String, nil] article title
    # @param description [String, nil] raw extracted description/content (not feed-rendered HTML)
    # @param url [String, Html2rss::Url, nil] canonical article URL
    # @param image [String, Html2rss::Url, nil] image URL for description / JSON Feed +image+
    # @param author [String, nil] author name
    # @param guid [String, Array, nil] explicit GUID override
    # @param published_at [String, Time, DateTime, nil] publication timestamp
    # @param enclosures [Array<Hash{Symbol => Object}>, nil] enclosure attribute hashes
    # @param categories [Array<String>, nil] category labels
    # @param scraper [Class, nil] scraper class that produced the article
    # rubocop:disable-next Metrics/ParameterLists -- eleven article keys stay explicit
    def initialize(id: nil, title: nil, description: nil, url: nil, image: nil, author: nil, guid: nil,
                   published_at: nil, enclosures: nil, categories: nil, scraper: nil)
      @to_h = { id:, title:, description:, url:, image:, author:, guid:, published_at:, enclosures:, categories:,
                scraper: }.compact.transform_values { freeze_option(_1) }.freeze

      @url = @image = @guid = @enclosures = @categories = @published_at = NOT_SET
    end

    # Checks if the article is valid based on the presence of URL, ID, and either title or description.
    # @return [Boolean] True if the article is valid, otherwise false.
    def valid?
      !url.to_s.empty? && (!title.to_s.empty? || !description.to_s.empty?) && !id.to_s.empty?
    end

    # @return [String, nil] stable article identifier
    def id = blank_string_to_nil(@to_h[:id])

    # @return [String, nil] article title
    def title = blank_string_to_nil(@to_h[:title])

    # Raw extracted description — feed HTML enrichment is {FeedBuilder::ItemPresentation.description_for}.
    #
    # @return [String, nil]
    def description = blank_string_to_nil(@to_h[:description])

    # @return [Url, nil]
    def url
      return @url unless @url == NOT_SET

      @url = Url.sanitize(@to_h[:url])
    end

    # @return [Url, nil]
    def image
      return @image unless @image == NOT_SET

      @image = Url.sanitize(@to_h[:image])
    end

    # @return [String, nil]
    def author = blank_string_to_nil(@to_h[:author])

    # Generates a unique identifier based on the URL and ID using CRC32.
    # @return [String]
    def guid
      return @guid unless @guid == NOT_SET

      @guid = Zlib.crc32(fetch_guid).to_s(36).encode('utf-8')
    end

    ##
    # Returns a deterministic fingerprint used to detect duplicate articles.
    #
    # @return [String, Integer]
    def deduplication_fingerprint
      dedup_from_url || dedup_from_id || dedup_from_guid || hash
    end

    # @return [Array<Html2rss::Article::Enclosure>] normalized enclosure objects
    def enclosures
      return @enclosures unless @enclosures == NOT_SET

      @enclosures = Array(@to_h[:enclosures])
                    .map { |enclosure| Enclosure.new(**enclosure) }
                    .freeze
    end

    # @return [Array<String>] normalized, unique category names
    def categories
      return @categories unless @categories == NOT_SET

      @categories = @to_h[:categories].dup.to_a.tap do |categories|
        categories.map! { |category| category.to_s.strip }
        categories.reject!(&:empty?)
        categories.uniq!
      end.freeze
    end

    # Parses and returns the published_at time.
    # @return [DateTime, nil]
    def published_at
      return @published_at unless @published_at == NOT_SET

      string = @to_h[:published_at].to_s.strip
      @published_at = string.empty? ? nil : DateTime.parse(string)
    rescue ArgumentError
      @published_at = nil
    end

    # @return [Class, nil] scraper class that produced this article
    def scraper
      @to_h[:scraper]
    end

    private

    ##
    # Marshal only the constructor payload so lazy +NOT_SET+ sentinels do not break
    # {FeedResult} cache round-trips.
    #
    # @return [Hash{Symbol => Object}]
    def marshal_dump = @to_h

    ##
    # @param payload [Hash{Symbol => Object}] constructor options from {#marshal_dump}
    # @return [void]
    def marshal_load(payload)
      initialize(**payload)
    end

    def freeze_option(value)
      case value
      when String then value.dup.freeze
      when Array then freeze_array_option(value)
      when Hash then value.transform_values { freeze_option(_1) }.freeze
      else value
      end
    end

    def freeze_array_option(value)
      value.map do |entry|
        entry.is_a?(Hash) ? entry.transform_values { freeze_option(_1) }.freeze : freeze_option(entry)
      end.freeze
    end

    def dedup_from_url
      return unless (value = url)

      [value.to_s, id].compact.join(DEDUP_FINGERPRINT_SEPARATOR)
    end

    def dedup_from_id
      return if id.to_s.empty?

      id
    end

    def dedup_from_guid
      value = guid
      return if value.to_s.empty?

      [value, title, description].compact.join(DEDUP_FINGERPRINT_SEPARATOR)
    end

    def fetch_guid
      guid = @to_h[:guid].map { |s| s.to_s.strip }.reject(&:empty?).join if @to_h[:guid].is_a?(Array)

      guid || [url, id].join('#!/')
    end

    def blank_string_to_nil(value)
      return if value.is_a?(String) && value.strip.empty?

      value
    end
  end
end
