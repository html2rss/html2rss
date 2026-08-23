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

  it 'omits wire fields from to_h', :aggregate_failures do
    expect(entry.to_h.keys).to contain_exactly(:id, :path, :directory, :channel, :parameters)
    expect(entry.to_h).not_to include(:source, :registry)
  end
end
