# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conditional Processing Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('conditional_processing_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples conditional_processing_site.yml]) }
  let(:html_file) { File.join(%w[spec examples conditional_processing_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }
  let(:titles) { items.map(&:title) }

  it_behaves_like 'generates valid RSS feed'
  it_behaves_like 'extracts valid item content'
  it_behaves_like 'extracts valid published dates'

  it 'extracts status information as categories' do
    items_with_status = items.select do |item|
      item.categories.any? { |cat| cat.content.is_a?(String) }
    end
    expect(items_with_status.size).to be > 0
  end
end
