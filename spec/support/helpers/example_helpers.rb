# frozen_string_literal: true

# Helper methods for HTML2RSS example specs that keep assertions aligned with the production pipeline.

require_relative 'configuration_helpers'

module ExampleHelpers
  include ConfigurationHelpers

  FIXTURE_ROOT = File.join('spec', 'examples').freeze

  def mock_request_service_with_html_fixture(fixture_name, url, content_type: 'text/html')
    stub_request_service(fixture_path(fixture_name, 'html'), url, content_type)
  end

  def mock_request_service_with_json_fixture(fixture_name, url, content_type: 'application/json')
    stub_request_service(fixture_path(fixture_name, 'json'), url, content_type)
  end

  def generate_feed_from_config(config, fixture_name, fixture_type = :html, url = 'https://example.com')
    case fixture_type
    when :html
      mock_request_service_with_html_fixture(fixture_name, url)
    when :json
      mock_request_service_with_json_fixture(fixture_name, url)
    else
      raise ArgumentError, "Invalid fixture_type: #{fixture_type}. Must be :html or :json"
    end

    channel_config = config.fetch(:channel).merge(url:)
    Html2rss.feed(config.merge(channel: channel_config))
  end

  def expect_feed_items(items, expected_items)
    expect(items.size).to eq(expected_items.size)
    expected_items.each_with_index do |expected, index|
      verify_item_expectations(items.fetch(index), expected, index)
    end
  end

  private

  def fixture_path(fixture_name, extension)
    File.join(FIXTURE_ROOT, "#{fixture_name}.#{extension}")
  end

  def stub_request_service(fixture_path, url, content_type)
    body = File.read(fixture_path)
    response_url = Html2rss::Url.from_relative(url, url)

    allow(Html2rss::RequestService).to receive(:execute).and_return(
      Html2rss::RequestService::Response.new(
        body:,
        url: response_url,
        headers: { 'content-type': content_type }
      )
    )
  end

  def verify_item_expectations(item, expected, index)
    aggregate_failures("item ##{index + 1}") do
      expect_item_title(item, expected)
      expect_item_link(item, expected)
      expect_item_description(item, expected)
      expect_item_categories(item, expected)
      expect_item_pub_date(item, expected)
      expect_item_enclosure(item, expected)
    end
  end

  def expect_item_title(item, expected)
    return unless expected.key?(:title)

    expect(item.title).to eq(expected[:title])
  end

  def expect_item_link(item, expected)
    return unless expected.key?(:link)

    expect_optional_value(item.link, expected[:link])
  end

  def expect_item_description(item, expected)
    Array(expected[:description_includes]).each do |snippet|
      expect(item.description).to include(snippet)
    end

    return unless expected.key?(:description_starts_with)

    expect(item.description).to start_with(expected[:description_starts_with])
  end

  def expect_item_categories(item, expected)
    return unless expected.key?(:categories)

    expect(item.categories.map(&:content)).to eq(expected[:categories])
  end

  def expect_item_pub_date(item, expected)
    return unless expected.key?(:pub_date)

    actual_pub_date = item.pubDate&.rfc2822
    expect_optional_value(actual_pub_date, expected[:pub_date])
  end

  def expect_item_enclosure(item, expected)
    return unless expected.key?(:enclosure)

    expected_enclosure = expected[:enclosure]
    if expected_enclosure.nil?
      expect(item.enclosure).to be_nil
      return
    end

    expect(item.enclosure).not_to be_nil
    expect_enclosure_attributes(item.enclosure, expected_enclosure)
  end

  def expect_enclosure_attributes(enclosure, expected)
    expect_enclosure_field(enclosure, expected, :url)
    expect_enclosure_field(enclosure, expected, :type)
    expect_enclosure_field(enclosure, expected, :length)
  end

  def expect_optional_value(actual, expected)
    expected.nil? ? expect(actual).to(be_nil) : expect(actual).to(eq(expected))
  end

  def expect_enclosure_field(enclosure, expected, field)
    return unless expected.key?(field)

    expect(enclosure.public_send(field)).to eq(expected[field])
  end
end

# Include the helper methods in RSpec configuration
RSpec.configure do |config|
  config.include ExampleHelpers
end
