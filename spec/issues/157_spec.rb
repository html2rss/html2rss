# frozen_string_literal: true

RSpec.describe 'issues/157', type: :system do
  subject do
    VCR.use_cassette('issues-157') do
      config = Html2rss.config_from_yaml_config('spec/issues/157.yml')
      Html2rss.feed(config)
    end
  end

  it 'builds a feed with one item, containing the sanitized <body> of the page as description', :aggregate_failures do
    expect(subject.items.size).to eq(1)
    expect(subject.items.first.title).to eq('Test string')
    expect(subject.items.first.description).to match(%r{<div>.*</div>})
  end
end
