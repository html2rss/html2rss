# frozen_string_literal: true

require 'time'

# rubocop:disable Metrics/ModuleLength -- Channel value object owns extract + freeze + Marshal
module Html2rss
  ##
  # Materialized channel metadata for feed builders and {FeedResult}.
  #
  # Extract once via {Channel.from_response}; builders consume this value object and
  # do not own channel extraction. Safe to Marshal (no Response / Nokogiri retained).
  # Strings and image URL are normalized and frozen at construction (including Marshal load).
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
  Channel = Data.define(:title, :url, :description, :language, :ttl, :last_build_date, :image, :author) do
    class << self
      ##
      # Materializes channel attributes from an HTTP response and optional overrides.
      #
      # @param response [Html2rss::RequestService::Response]
      # @param overrides [Hash{Symbol => Object}] optional overrides for channel attributes
      # @return [Html2rss::Channel]
      def from_response(response, overrides: {})
        new(
          title: title_for(response, overrides),
          url: url_for(response),
          description: description_for(response, overrides),
          language: language_for(response, overrides),
          ttl: ttl_for(response, overrides),
          last_build_date: last_build_date_for(response),
          image: image_for(response, overrides),
          author: author_for(response, overrides)
        )
      end

      private

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

      def language_for(response, overrides)
        return overrides[:language] if overrides[:language]

        if (language_code = headers(response)['content-language']&.match(/^([a-z]{2})/))
          return language_code[0]
        end

        return unless html_response?(response)

        parsed_body(response)['lang'] || parsed_body(response).at_css('[lang]')&.[]('lang')
      end

      def author_for(response, overrides)
        return overrides[:author] if overrides[:author]
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
    # rubocop:disable Metrics/ParameterLists -- Data.define members are the channel contract
    def initialize(title:, url:, description:, language:, ttl:, last_build_date:, image:, author:)
      super(
        title: freeze_string(title),
        url: url.is_a?(Url) ? url : Url.from_absolute(url),
        description: freeze_string(description),
        language: language && freeze_string(language),
        ttl: Integer(ttl),
        last_build_date: normalize_last_build_date(last_build_date),
        image: normalize_image(image),
        author: author && freeze_string(author)
      )
    end
    # rubocop:enable Metrics/ParameterLists

    private

    def marshal_dump = [title, url, description, language, ttl, last_build_date, image, author]

    def marshal_load(payload)
      initialize(
        title: payload[0], url: payload[1], description: payload[2], language: payload[3],
        ttl: payload[4], last_build_date: payload[5], image: payload[6], author: payload[7]
      )
    end

    def freeze_string(value) = value.to_s.dup.freeze

    def normalize_image(value)
      return value if value.is_a?(Url)
      return if value.nil?

      Url.sanitize(value.to_s)
    end

    def normalize_last_build_date(value)
      return value if value.is_a?(Time)
      raise ArgumentError, 'last_build_date must be a Time or HTTP-date String' unless value.is_a?(String)

      Time.httpdate(value)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
