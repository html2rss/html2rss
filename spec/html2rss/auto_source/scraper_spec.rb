# frozen_string_literal: true

require 'rspec'

RSpec.describe Html2rss::AutoSource::Scraper do
  it { is_expected.to be_a(Module) }
  it { expect(described_class::SCRAPERS).to be_an(Array) }

  describe '.from(parsed_body)' do
    context 'when suitable scraper is found' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><article><a href="#"></a></article></body></html>')
      end

      it 'returns an array of scrapers' do
        expect(described_class.from(parsed_body)).to be_an(Array)
      end
    end

    context 'when no suitable scraper is found' do
      let(:parsed_body) { Nokogiri::HTML('<html><body></body></html>') }

      it 'raises NoScraperFound error' do
        expect do
          described_class.from(parsed_body)
        end.to raise_error(Html2rss::AutoSource::Scraper::NoScraperFound)
      end
    end
  end
end
