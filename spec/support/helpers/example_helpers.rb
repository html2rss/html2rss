# frozen_string_literal: true

# Helper methods for HTML2RSS example specs
# These methods provide common setup and validation patterns
# to make tests more readable and maintainable.

require 'time'

require_relative 'configuration_helpers'

module ExampleHelpers
  include ConfigurationHelpers

  DEFAULT_CHANNEL_TIME_ZONE = Html2rss::Config.default_config.dig(:channel, :time_zone)

  # Loads an example HTML fixture from the spec/examples directory
  # @param fixture_name [String] The name of the HTML fixture file (without .html extension)
  # @return [String] The HTML content as a string
  # @example
  #   html_content = load_html_fixture('combined_scraper_sources')
  def load_html_fixture(fixture_name)
    html_file = File.join(%w[spec examples], "#{fixture_name}.html")
    File.read(html_file)
  end

  # Loads an example JSON fixture from the spec/examples directory
  # @param fixture_name [String] The name of the JSON fixture file (without .json extension)
  # @return [String] The JSON content as a string
  # @example
  #   json_content = load_json_fixture('json_api_site')
  def load_json_fixture(fixture_name)
    json_file = File.join(%w[spec examples], "#{fixture_name}.json")
    File.read(json_file)
  end

  # Mocks the request service to return HTML content from a fixture
  # @param fixture_name [String] The name of the HTML fixture file
  # @param url [String] The URL to use for the mock response (default: 'https://example.com')
  # @param content_type [String] The content type header (default: 'text/html')
  # @example
  #   mock_request_service_with_html_fixture('combined_scraper_sources', 'https://example.com')
  def mock_request_service_with_html_fixture(fixture_name, url = 'https://example.com', content_type = 'text/html')
    html_content = load_html_fixture(fixture_name)
    url_object = create_url_object(url)
    mock_request_service(html_content, url_object, content_type)
  end

  # Mocks the request service to return JSON content from a fixture
  # @param fixture_name [String] The name of the JSON fixture file
  # @param url [String] The URL to use for the mock response (default: 'https://example.com/api')
  # @param content_type [String] The content type header (default: 'application/json')
  # @example
  #   mock_request_service_with_json_fixture('json_api_site', 'https://api.example.com/posts')
  def mock_request_service_with_json_fixture(fixture_name, url = 'https://example.com/api',
                                             content_type = 'application/json')
    json_content = load_json_fixture(fixture_name)
    url_object = create_url_object(url)
    mock_request_service(json_content, url_object, content_type)
  end

  # Builds a Selectors context that mirrors how post processors are invoked in production.
  # @param channel_url [String]
  # @param time_zone [String, nil]
  # @return [Html2rss::Selectors::Context]
  def build_post_processor_context(channel_url:, time_zone: nil)
    Html2rss::Selectors::Context.new(
      config: { channel: { url: channel_url, time_zone: time_zone || DEFAULT_CHANNEL_TIME_ZONE } }
    )
  end

  # Applies the sanitize_html post processor to a fragment using the same configuration
  # that the feed uses.
  # @param fragment [String]
  # @param channel_url [String]
  # @return [String, nil]
  def sanitize_fragment(fragment, channel_url:)
    Html2rss::Selectors::PostProcessors::SanitizeHtml.get(fragment, channel_url)
  end

  # Applies the html_to_markdown post processor to a fragment using production settings.
  # @param fragment [String]
  # @param channel_url [String]
  # @param time_zone [String, nil]
  # @return [String]
  def markdown_from_fragment(fragment, channel_url:, time_zone: nil)
    context = build_post_processor_context(channel_url:, time_zone:)
    Html2rss::Selectors::PostProcessors::HtmlToMarkdown.new(fragment, context).get
  end

  # Parses a human readable timestamp the same way parse_time post processor does and
  # returns a Time instance for easier assertions.
  # @param value [String]
  # @param channel_url [String]
  # @param time_zone [String, nil]
  # @return [Time]
  def parse_time_to_time(value, channel_url:, time_zone: nil)
    context = build_post_processor_context(channel_url:, time_zone:)
    parsed = Html2rss::Selectors::PostProcessors::ParseTime.new(value, context).get
    Time.rfc2822(parsed)
  end

  # Resolves the provided relative URL against the supplied channel URL.
  # @param href [String, nil]
  # @param channel_url [String]
  # @return [String]
  def absolute_url_for(href, channel_url)
    Html2rss::Url.from_relative(href, channel_url).to_s
  end

  # Generates an RSS feed from a configuration with mocked request service
  # @param config [Hash] The HTML2RSS configuration hash
  # @param fixture_name [String] The name of the fixture file to use
  # @param fixture_type [Symbol] The type of fixture (:html or :json)
  # @param url [String] The URL to use for the mock response
  # @return [RSS::Rss] The generated RSS feed
  # @example
  #   feed = generate_feed_from_config(config, 'combined_scraper_sources', :html)
  def generate_feed_from_config(config, fixture_name, fixture_type = :html, url = 'https://example.com')
    case fixture_type
    when :html
      mock_request_service_with_html_fixture(fixture_name, url)
    when :json
      mock_request_service_with_json_fixture(fixture_name, url)
    else
      raise ArgumentError, "Invalid fixture_type: #{fixture_type}. Must be :html or :json"
    end

    # Update the config with the URL for proper URL handling
    config_with_url = config.merge(channel: config[:channel].merge(url:))
    Html2rss.feed(config_with_url)
  end

  # Extracts all item titles from an RSS feed
  # @param feed [RSS::Rss] The RSS feed
  # @return [Array<String>] Array of item titles
  # @example
  #   titles = extract_item_titles(feed)
  def extract_item_titles(feed)
    return [] unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.filter_map(&:title)
  end

  # Extracts all item descriptions from an RSS feed
  # @param feed [RSS::Rss] The RSS feed
  # @return [Array<String>] Array of item descriptions
  # @example
  #   descriptions = extract_item_descriptions(feed)
  def extract_item_descriptions(feed)
    return [] unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.filter_map(&:description)
  end

  # Extracts all item links from an RSS feed
  # @param feed [RSS::Rss] The RSS feed
  # @return [Array<String>] Array of item links
  # @example
  #   links = extract_item_links(feed)
  def extract_item_links(feed)
    return [] unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.filter_map(&:link)
  end

  # Extracts all item published dates from an RSS feed
  # @param feed [RSS::Rss] The RSS feed
  # @return [Array<Time>] Array of item published dates (excluding nil values)
  # @example
  #   dates = extract_item_published_dates(feed)
  def extract_item_published_dates(feed)
    return [] unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.filter_map(&:pubDate)
  end

  # Extracts all categories from RSS feed items
  # @param feed [RSS::Rss] The RSS feed
  # @return [Array<String>] Array of all category contents
  # @example
  #   categories = extract_all_categories(feed)
  def extract_all_categories(feed)
    return [] unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.flat_map { |item| item.categories.map(&:content) }.compact.uniq
  end

  # Validates that all strings in an array are non-empty
  # @param strings [Array<String>] Array of strings to validate
  # @return [Boolean] True if all strings are non-empty
  # @example
  #   expect(all_strings_non_empty?(titles)).to be true
  def all_strings_non_empty?(strings)
    strings.is_a?(Array) && strings.all? { |str| str.is_a?(String) && !str.strip.empty? }
  end

  # Validates that all times in an array are valid Time objects
  # @param times [Array] Array of objects to validate as times
  # @return [Boolean] True if all objects are valid Time objects
  # @example
  #   expect(all_valid_times?(published_dates)).to be true
  def all_valid_times?(times)
    times.is_a?(Array) && times.all?(Time)
  end

  # Creates a descriptive test name for configuration validation
  # @param config_name [String] The name of the configuration
  # @param validation_type [String] The type of validation being performed
  # @return [String] A descriptive test name
  # @example
  #   test_name = config_validation_test_name('combined_scraper_sources', 'basic structure')
  def config_validation_test_name(config_name, validation_type)
    "#{config_name} configuration #{validation_type}"
  end

  # Creates a descriptive test name for RSS feed validation
  # @param validation_type [String] The type of validation being performed
  # @return [String] A descriptive test name
  # @example
  #   test_name = rss_validation_test_name('generates valid feed')
  def rss_validation_test_name(validation_type)
    "RSS feed #{validation_type}"
  end

  private

  def create_url_object(url)
    url.is_a?(String) ? Html2rss::Url.from_relative(url, url) : url
  end

  def mock_request_service(content, url_object, content_type)
    # Mock the execute method on the RequestService class (which delegates to instance)
    allow(Html2rss::RequestService).to receive(:execute).and_return(
      Html2rss::RequestService::Response.new(
        body: content,
        url: url_object,
        headers: { 'content-type': content_type }
      )
    )
  end
end

# Include the helper methods in RSpec configuration
RSpec.configure do |config|
  config.include ExampleHelpers
end
