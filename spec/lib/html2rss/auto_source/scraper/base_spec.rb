# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Base do
  it 'is Enumerable and keeps the page and url it was built with', :aggregate_failures do
    expect(described_class).to include(Enumerable)
    expect(ScraperProbe.new(:page, url: 'https://example.com').to_a).to eq([:page, 'https://example.com'])
  end

  it 'answers extractable? from the subclass articles? for the instance page', :aggregate_failures do
    expect(ScraperProbe.new(:detectable, url: 'https://example.com')).to be_extractable
    expect(ScraperProbe.new(:other, url: 'https://example.com')).not_to be_extractable
  end

  it 'leaves request_slots and options_key to each scraper', :aggregate_failures do
    expect(described_class).not_to respond_to(:request_slots)
    expect(described_class).not_to respond_to(:options_key)
  end
end
