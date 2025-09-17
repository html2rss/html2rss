# frozen_string_literal: true

# Shared examples for RSS feed generation with mocked request service
# These examples provide common patterns for testing RSS feed generation

RSpec.shared_examples 'generates feed with mocked request' do |fixture_type = :html, url = 'https://example.com'|
  subject(:feed) do
    case fixture_type
    when :html
      mock_request_service_with_html_fixture(fixture_name, url)
    when :json
      mock_request_service_with_json_fixture(fixture_name, url)
    end

    Html2rss.feed(config)
  end

  let(:items) { feed.items }

  it_behaves_like 'generates valid RSS feed'
  it_behaves_like 'extracts valid item content'
  it_behaves_like 'extracts valid published dates'
end

RSpec.shared_examples 'generates feed with HTML fixture' do |fixture_name, url = 'https://example.com'|
  let(:fixture_name) { fixture_name }
  it_behaves_like 'generates feed with mocked request', :html, url
end

RSpec.shared_examples 'generates feed with JSON fixture' do |fixture_name, url = 'https://example.com'|
  let(:fixture_name) { fixture_name }
  it_behaves_like 'generates feed with mocked request', :json, url
end
