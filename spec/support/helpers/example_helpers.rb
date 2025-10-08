# frozen_string_literal: true

# Helper methods for HTML2RSS example specs
# These helpers keep the specs focused on intent while staying close to the
# production pipeline so the assertions remain trustworthy.

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

    items.zip(expected_items).each_with_index do |(item, expected), index|
      aggregate_failures("item ##{index + 1}") do
        expect(item.title).to eq(expected[:title]) if expected.key?(:title)

        if expected.key?(:link)
          expected_link = expected[:link]
          expected_link.nil? ? expect(item.link).to(be_nil) : expect(item.link).to(eq(expected_link))
        end

        Array(expected[:description_includes]).each do |snippet|
          expect(item.description).to include(snippet)
        end

        if expected.key?(:description_starts_with)
          expect(item.description).to start_with(expected[:description_starts_with])
        end

        if expected.key?(:categories)
          expect(item.categories.map(&:content)).to eq(expected[:categories])
        end

        if expected.key?(:pub_date)
          actual_pub_date = item.pubDate&.rfc2822
          expected[:pub_date].nil? ? expect(actual_pub_date).to(be_nil) : expect(actual_pub_date).to(eq(expected[:pub_date]))
        end

        next unless expected.key?(:enclosure)

        if expected[:enclosure].nil?
          expect(item.enclosure).to be_nil
        else
          expect(item.enclosure).not_to be_nil
          enclosure = item.enclosure
          expect(enclosure.url).to eq(expected[:enclosure][:url]) if expected[:enclosure].key?(:url)
          expect(enclosure.type).to eq(expected[:enclosure][:type]) if expected[:enclosure].key?(:type)
          if expected[:enclosure].key?(:length)
            expect(enclosure.length).to eq(expected[:enclosure][:length])
          end
        end
      end
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
        body: body,
        url: response_url,
        headers: { 'content-type': content_type }
      )
    )
  end
end

# Include the helper methods in RSpec configuration
RSpec.configure do |config|
  config.include ExampleHelpers
end
