# frozen_string_literal: true

RSpec.describe Html2rss::SST::Attrs do
  describe '.build' do
    it 'omits blank fields and freezes class names', :aggregate_failures do
      attrs = described_class.build(href: ' /x ', class_names: %w[a b], src: ' ')

      expect(attrs.href).to eq('/x')
      expect(attrs.src).to be_nil
      expect(attrs.class_names).to eq(%w[a b])
      expect(attrs.class_names).to be_frozen
    end

    it 'rejects Hash class_names' do
      expect { described_class.build(class_names: { a: 1 }) }.to raise_error(ArgumentError)
    end

    it 'exposes typed readers, class_attr, and raw', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      attrs = described_class.build(
        href: '/a',
        id: 'x',
        class_names: %w[one two],
        datetime: '2026-01-01',
        itemprop: 'datePublished',
        style: 'color:red',
        srcset: 'a 1w',
        type: 'image/png',
        raw: { 'data-category' => 'News' }
      )

      expect(attrs.href).to eq('/a')
      expect(attrs.id).to eq('x')
      expect(attrs.class_attr).to eq('one two')
      expect(attrs.datetime).to eq('2026-01-01')
      expect(attrs.itemprop).to eq('datePublished')
      expect(attrs.style).to eq('color:red')
      expect(attrs.srcset).to eq('a 1w')
      expect(attrs.type).to eq('image/png')
      expect(attrs.raw['data-category']).to eq('News')
      expect(described_class.empty.href).to be_nil
    end

    it 'rejects non-Hash raw' do
      expect { described_class.build(raw: []) }.to raise_error(ArgumentError)
    end
  end
end
