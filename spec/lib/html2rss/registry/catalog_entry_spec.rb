# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::CatalogEntry do
  subject(:entry) do
    described_class.new(
      id: 'example.com/news',
      path: '/example.com/news.rss',
      directory: { title: 'Example' },
      channel: { url: 'https://example.com/news' },
      parameters: { schema: {}, defaults: {} }
    )
  end

  it 'serializes domain fields to a plain hash', :aggregate_failures do
    expect(entry.to_h[:id]).to eq('example.com/news')
    expect(entry.to_h[:path]).to eq('/example.com/news.rss')
  end
end
