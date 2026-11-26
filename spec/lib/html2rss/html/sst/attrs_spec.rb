# frozen_string_literal: true

RSpec.describe Html2rss::Html::SST::Attrs do
  describe '.build' do
    it 'omits blank fields and freezes class names', :aggregate_failures do
      attrs = described_class.build(href: ' /x ', class_names: %w[a b], src: ' ')

      expect(attrs.href).to eq('/x')
      expect(attrs.src).to be_nil
      expect(attrs.class_names).to eq(%w[a b])
      expect(attrs.class_names).to be_frozen
    end

    it 'rejects Hash class_names, naming the class it got' do
      expect { described_class.build(class_names: { a: 1 }) }
        .to raise_error(Html2rss::Html::SST::InvalidError, 'class_names must be an Array, got Hash')
    end

    it 'exposes typed readers, class_attr, and raw', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      attrs = described_class.build(
        href: '/a',
        src: '/a.png',
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
      expect(attrs.src).to eq('/a.png')
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

    it 'rejects non-Hash raw, naming the class it got' do
      expect { described_class.build(raw: []) }
        .to raise_error(Html2rss::Html::SST::InvalidError, 'raw must be a Hash, got Array')
    end

    it 'maps every blank scalar field to nil', :aggregate_failures do
      %i[href src id datetime itemprop style srcset type].each do |field|
        expect(described_class.build(field => " \t\n ").public_send(field)).to be_nil
      end
    end

    it 'strips surrounding whitespace from scalar fields and stringifies them', :aggregate_failures do
      attrs = described_class.build(href: "\n /x \t", id: 42, type: :png)

      expect(attrs.href).to eq('/x')
      expect(attrs.id).to eq('42')
      expect(attrs.type).to eq('png')
      expect(attrs.href).to be_frozen
    end

    it 'defaults class names and raw to empty frozen collections', :aggregate_failures do
      attrs = described_class.build

      expect(attrs.class_names).to eq([])
      expect(attrs.raw).to eq({})
      expect(attrs.raw).to be_frozen
    end

    it 'coerces a class list that mixes Strings with other tokens', :aggregate_failures do
      attrs = described_class.build(class_names: ['a', :b])

      expect(attrs.class_names).to eq(%w[a b]).and be_frozen
      expect(attrs.class_names).to all(be_frozen)
    end

    it 'shares the empty collections for empty input', :aggregate_failures do
      attrs = described_class.build(class_names: [], raw: {})

      expect(attrs.class_names).to be(described_class.empty.class_names)
      expect(attrs.raw).to be(described_class.empty.raw)
    end

    it 'freezes String class names in place, taking ownership of the list', :aggregate_failures do
      tokens = [+'a', +'b']
      attrs = described_class.build(class_names: tokens)

      expect(attrs.class_names).to be(tokens)
      expect(tokens).to be_frozen.and all(be_frozen)
      expect { attrs.class_names.first << 'x' }.to raise_error(FrozenError)
    end

    it 'freezes a raw Hash of frozen values in place, taking ownership of it', :aggregate_failures do
      raw = { 'data-a' => 'x', 'rel' => 'next' }
      attrs = described_class.build(raw:)

      expect(attrs.raw).to be(raw)
      expect(raw).to be_frozen
      expect { attrs.raw['data-a'] << 'x' }.to raise_error(FrozenError)
    end

    it 'freezes the String values of a raw Hash in place too', :aggregate_failures do
      value = +'x'
      attrs = described_class.build(raw: { 'data-a' => value })

      expect(attrs.raw['data-a']).to be(value).and be_frozen
    end

    it 'copies a raw Hash that holds other values, leaving the caller Hash alone', :aggregate_failures do
      raw = { 'data-a' => +'x', 'data-n' => 1 }
      attrs = described_class.build(raw:)

      expect(attrs.raw).to eq('data-a' => 'x', 'data-n' => '1').and be_frozen
      expect(attrs.raw.values).to all(be_frozen)
      expect(raw).not_to be_frozen
    end

    it 'stringifies and freezes class names and raw values', :aggregate_failures do
      attrs = described_class.build(class_names: [:x, 3], raw: { 'data-n' => 1 })

      expect(attrs.class_names).to eq(%w[x 3]).and be_frozen
      expect(attrs.class_names.first).to be_frozen
      expect(attrs.raw).to eq('data-n' => '1')
      expect(attrs.raw['data-n']).to be_frozen
    end
  end
end
