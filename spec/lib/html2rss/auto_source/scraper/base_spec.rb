# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Base do
  let(:scraper_class) do
    Class.new(described_class) do
      define_singleton_method(:articles?) { |parsed_body| parsed_body == :detectable }
      define_method(:each) { |&block| [parsed_body, url].each(&block) }
    end
  end

  it 'is Enumerable and keeps the page and url it was built with', :aggregate_failures do
    expect(described_class).to include(Enumerable)
    expect(scraper_class.new(:page, url: 'https://example.com').to_a).to eq([:page, 'https://example.com'])
  end

  it 'answers extractable? from the subclass articles? for the instance page', :aggregate_failures do
    expect(scraper_class.new(:detectable, url: 'https://example.com')).to be_extractable
    expect(scraper_class.new(:other, url: 'https://example.com')).not_to be_extractable
  end

  it 'leaves request_slots and options_key to each scraper', :aggregate_failures do
    expect(described_class).not_to respond_to(:request_slots)
    expect(described_class).not_to respond_to(:options_key)
  end
end
