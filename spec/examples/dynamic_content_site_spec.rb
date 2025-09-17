# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('dynamic_content_site', 'https://example.com/news')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples dynamic_content_site.yml]) }
  let(:html_file) { File.join(%w[spec examples dynamic_content_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }

  it_behaves_like 'generates valid RSS feed'
  it_behaves_like 'extracts valid item content'
  it_behaves_like 'extracts valid published dates'

  it 'handles dynamic content loading', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    expect(items.size).to be > 0

    items.each do |item|
      expect(item.title).not_to be_nil
      expect(item.link).not_to be_nil
      expect(item.description).not_to be_nil
      expect(item.pubDate).not_to be_nil
    end
  end
end
