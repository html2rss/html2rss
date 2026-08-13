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

    it 'is Attrs Data, not a Hash bag', :aggregate_failures do
      attrs = described_class.build(href: '/a')
      expect(attrs).to be_a(described_class)
      expect(attrs).not_to be_a(Hash)
    end
  end
end
