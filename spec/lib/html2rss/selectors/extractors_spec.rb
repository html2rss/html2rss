# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors do
  let(:doc) { Nokogiri::HTML('<html><body><p>a</p><p>b</p><a href="/a">x</a><b>b</b></body></html>') }

  describe '.call(attribute_options, xml)' do
    context 'with valid extractor name' do
      it do
        expect(described_class.call({ extractor: 'static' }, nil)).to be_nil
      end
    end
  end

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

  describe '.call dispatch' do
    it 'uses the text extractor and all matches when no extractor is configured' do
      expect(described_class.call({ selector: 'p' }, doc)).to eq('ab')
    end

    it 'reads the attribute named in the config from the first match' do
      expect(described_class.call({ extractor: 'attribute', attribute: 'href', selector: 'a' }, doc)).to eq('/a')
    end

    it 'resolves relative hrefs against the base_url argument', :aggregate_failures do
      href = described_class.call({ extractor: 'href', selector: 'a' }, doc, base_url: 'http://x.test/dir/')

      expect(href.to_s).to eq('http://x.test/a')
    end

    it 'falls back to the base_url in the config when no argument is given' do
      href = described_class.call({ extractor: 'href', selector: 'a', base_url: 'http://y.test/' }, doc)

      expect(href.to_s).to eq('http://y.test/a')
    end

    it 'lets an explicit selector argument override the config selector' do
      expect(described_class.call({ extractor: 'text', selector: 'p' }, doc, selector: 'b')).to eq('b')
    end

    it 'uses the node as-is when the configured selector is nil' do
      node = Nokogiri::HTML('<p>x</p>').at('p')

      expect(described_class.call({ extractor: 'text', selector: nil }, node)).to eq('x')
    end

    it 'returns the outer html of the selected element' do
      expect(described_class.call({ extractor: 'html', selector: 'a' }, doc)).to eq('<a href="/a">x</a>')
    end

    it 'accepts the extractor name as a symbol' do
      expect(described_class.call({ extractor: :static, static: 'S' }, nil)).to eq('S')
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
