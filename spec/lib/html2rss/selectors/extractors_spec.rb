# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors do
  let(:doc) { Nokogiri::HTML('<html><body><p>a</p><p>b</p><a href="/a">x</a><b>b</b></body></html>') }

  describe '.element' do
    it 'returns the node itself when no selector is given' do
      expect(described_class.element(doc, nil)).to be(doc)
    end

    it 'returns every match for a selector by default' do
      expect(described_class.element(doc, 'p').size).to eq(2)
    end

    it 'returns only the first match when first is requested', :aggregate_failures do
      first = described_class.element(doc, 'p', first: true)

      expect(first).to be_a(Nokogiri::XML::Element)
      expect(first.text).to eq('a')
    end
  end

  describe 'schema export of every extractor' do
    it 'exports each extractor class with its own registry name, description and examples', :aggregate_failures do
      described_class::NAME_TO_CLASS.each do |name, klass|
        expect(klass.schema_export).to eq(
          Html2rss::Selectors::SchemaExport.for_extractor(name:, klass:)
        )
      end
    end
  end
end
