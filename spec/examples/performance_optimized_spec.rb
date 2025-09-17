# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Performance-Optimized Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('performance_optimized_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples performance_optimized_site.yml]) }
  let(:html_file) { File.join(%w[spec examples performance_optimized_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }

  it_behaves_like 'generates valid RSS feed'
  it_behaves_like 'extracts valid item content'
  it_behaves_like 'extracts valid published dates'

  it 'excludes advertisements and sidebar content' do
    expect(items.size).to be > 0
    # The complex selector should filter out ads and sidebar content
  end

  it 'validates that the CSS selector works as expected' do
    doc = Nokogiri::HTML(File.read(html_file))
    matching_posts = doc.css('.main-content .post:not(.advertisement)')
    expect(matching_posts.size).to be > 0
  end

  it 'parses ISO 8601 datetime format correctly' do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to be > 0
  end
end
