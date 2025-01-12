# frozen_string_literal: true

RSpec.describe 'issues/157', type: :system do
  # https://github.com/html2rss/html2rss/issues/157

  subject do
    VCR.use_cassette('issues-157') do
      Html2rss.feed(
        channel: { url: 'https://google.com' },
        selectors: {
          items: { selector: 'html' },
          title: {
            extractor: 'static',
            static: 'Test string'
          },
          description: {
            selector: 'body',
            extractor: 'html',
            post_process: {
              name: 'sanitize_html'
            }
          }
        }
      )
    end
  end

  it 'builds a feed with one item, containing the sanitized <body> of the page as description', :aggregate_failures do
    expect(subject.items.size).to eq(1)
    expect(subject.items.first.title).to eq('Test string')
    expect(subject.items.first.description).to match(%r{<div>.*</div>})
  end
end
