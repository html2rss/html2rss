# frozen_string_literal: true

require 'time'

module Html2rss
  Channel = Data.define(
    :title, :url, :description, :language, :ttl, :last_build_date, :image, :author, :categories, :explicit
  )

  ##
  # Materialized channel metadata for feed builders and {FeedResult}.
  #
  # Extract once via {Channel.from_response}; builders consume this value object and
  # do not own channel extraction. Safe to Marshal (no Response / Nokogiri retained).
  # Strings and image URL are normalized and frozen at construction (including Marshal load).
  #
  # The author is the config +channel.author+, else the followed native feed's author
  # ({Syndication::ChannelFacts}), else the page's +<meta name="author">+. Categories and the explicit
  # flag come only from that feed, when it states them.
  #
  # @!attribute [r] title
  #   @return [String]
  # @!attribute [r] url
  #   @return [Html2rss::Url]
  # @!attribute [r] description
  #   @return [String]
  # @!attribute [r] language
  #   @return [String, nil]
  # @!attribute [r] ttl
  #   @return [Integer]
  # @!attribute [r] last_build_date
  #   @return [Time]
  # @!attribute [r] image
  #   @return [Html2rss::Url, nil]
  # @!attribute [r] author
  #   @return [String, nil]
  # @!attribute [r] categories
  #   @return [Array<Array<String>>] each category followed by its subcategories (empty when unstated)
  # @!attribute [r] explicit
  #   @return [Boolean, nil] whether the content is declared explicit; nil when unstated
  class Channel # rubocop:disable Metrics/ClassLength -- Channel value object owns extract + freeze + Marshal
    # No overrides: shared, so resolving a page's language allocates no default Hash.
    NO_OVERRIDES = {}.freeze
    private_constant :NO_OVERRIDES

    class << self
      ##
      # Materializes channel attributes from an HTTP response and optional overrides.
      #
      # @param response [Html2rss::RequestService::Response]
      # @param overrides [Hash{Symbol => Object}] optional overrides for channel attributes
      # @param feed [Html2rss::Syndication::ChannelFacts, nil] what the followed native feed states
      # @return [Html2rss::Channel]
      def from_response(response, overrides: {}, feed: nil) # rubocop:disable Metrics/MethodLength -- one line per member
        new(
          title: title_for(response, overrides),
          url: url_for(response),
          description: description_for(response, overrides),
          language: language_for(response, overrides),
          ttl: ttl_for(response, overrides),
          last_build_date: last_build_date_for(response),
          image: image_for(response, overrides),
          author: overrides[:author] || feed&.author || meta_author(response),
          categories: feed&.categories || [],
          explicit: feed&.explicit
        )
      end

      ##
      # The language of a page: the config override, else the +Content-Language+ header, else the document
      # root's +lang+. The one resolution of the page language; {Vocabulary.[]} scopes the heuristics by it. A
      # header's primary tag must be exactly two letters (+en-US+ is +en+, +de, en+ is +de+; +jav+ is not +ja+).
      #
      # @param response [Html2rss::RequestService::Response]
      # @param overrides [Hash{Symbol => Object}] optional channel overrides (+:language+)
      # @return [String, nil]
      def language_for(response, overrides = NO_OVERRIDES)
        return overrides[:language] if overrides[:language]

        language_code = header_language(response)
        return language_code if language_code

        return unless html_response?(response)

        root_language(parsed_body(response))
      end

      private

      # The header's primary tag, lowercased; the header name and tag are case-insensitive (BCP 47).
      def header_language(response)
        response.header('content-language').to_s.downcase(:ascii)[/\A[a-z]{2}(?![a-z])/]
      end

      # Fallback RSS ttl (in minutes) when no cache directives are present.
      def default_ttl_in_minutes = 360

      # Description template used when no explicit or discovered description exists.
      def default_description_template = 'Latest items from %<url>s'

      def url_for(response) = Html2rss::Url.from_absolute(response.url)

      def title_for(response, overrides)
        return overrides[:title] if overrides[:title]

        title = parsed_title(response)
        return title if title

        url_for(response).channel_titleized
      end

      def parsed_title(response)
        return unless html_response?(response)

        title = parsed_body(response).at_css('head > title')&.text.to_s
        return if title.empty?

        title.gsub(/\s+/, ' ').strip
      end

      def description_for(response, overrides)
        return overrides[:description] unless overrides[:description].to_s.empty?

        description = meta_description(response)
        return format(default_description_template, url: url_for(response)) if description.to_s.empty?

        description
      end

      def meta_description(response)
        return unless html_response?(response)

        parsed_body(response).at_css('meta[name="description"]')&.[]('content')
      end

      def ttl_for(response, overrides)
        calculated = if overrides[:ttl]
                       overrides[:ttl].to_i
                     elsif (max_age = headers(response)['cache-control']&.match(/max-age=(\d+)/)&.[](1))
                       max_age.to_i.fdiv(60).ceil
                     else
                       default_ttl_in_minutes
                     end

        min_ttl = Html2rss.defaults.min_ttl
        min_ttl ? [calculated, min_ttl].max : calculated
      end

      def root_language(document)
        lang = document.root&.[]('lang')
        lang if lang&.match?(/\S/)
      end

      def meta_author(response)
        return unless html_response?(response)

        parsed_body(response).at_css('meta[name="author"]')&.[]('content')
      end

      def last_build_date_for(response)
        header = headers(response)['last-modified']
        return Time.now unless header

        Time.httpdate(header)
      rescue ArgumentError
        Time.now
      end

      def image_for(response, overrides)
        return overrides[:image] if overrides[:image]
        return unless html_response?(response)

        if (image_url = parsed_body(response).at_css('meta[property="og:image"]')&.[]('content'))
          Url.sanitize(image_url)
        end
      end

      def parsed_body(response) = response.parsed_body
      def headers(response) = response.headers
      def html_response?(response) = response.html_response?
    end

    ##
    # @param title [String]
    # @param url [Html2rss::Url, String]
    # @param description [String]
    # @param language [String, nil]
    # @param ttl [Integer]
    # @param last_build_date [Time, String]
    # @param image [Html2rss::Url, String, nil]
    # @param author [String, nil]
    # @param categories [Array<Array<String>>] each category followed by its subcategories
    # @param explicit [Boolean, nil]
    # rubocop:disable-next Metrics/ParameterLists, Metrics/MethodLength -- Data.define members are the channel contract
    def initialize(title:, url:, description:, language:, ttl:, last_build_date:, image:, author:,
                   categories: [], explicit: nil)
      super(
        title: freeze_string(title),
        url: url.is_a?(Url) ? url : Url.from_absolute(url),
        description: freeze_string(description),
        language: language && freeze_string(language),
        ttl: Integer(ttl),
        last_build_date: normalize_last_build_date(last_build_date),
        image: normalize_image(image),
        author: author && freeze_string(author),
        categories: categories.map { |path| path.map { freeze_string(_1) }.freeze }.freeze,
        explicit:
      )
    end

    private

    def marshal_dump = [title, url, description, language, ttl, last_build_date, image, author, categories, explicit]

    def marshal_load((title, url, description, language, ttl, last_build_date, image, author, categories, explicit))
      initialize(title:, url:, description:, language:, ttl:, last_build_date:, image:, author:, categories:,
                 explicit:)
    end

    def freeze_string(value) = value.to_s.dup.freeze

    def normalize_image(value)
      return value if value.is_a?(Url)
      return if value.nil?

      Url.sanitize(value.to_s)
    end

    def normalize_last_build_date(value)
      return value if value.is_a?(Time)
      raise InvalidOption, 'last_build_date must be a Time or HTTP-date String' unless value.is_a?(String)

      Time.httpdate(value)
    end
  end
end
