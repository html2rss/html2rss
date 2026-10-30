# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Attribute do
  subject { described_class.new(xml, **options).call }

  let(:xml) { Nokogiri.HTML('<div><time datetime="2019-07-01">...</time></div>') }
  let(:options) { { selector: 'time', attribute: 'datetime' } }

  it { is_expected.to eq '2019-07-01' }

  it 'returns an empty string when no element matches' do
    expect(described_class.new(xml, selector: 'span', attribute: 'datetime').call).to eq ''
  end

  it 'returns an empty string when the attribute is missing' do
    expect(described_class.new(xml, selector: 'time', attribute: 'title').call).to eq ''
  end

  it 'accepts omitted attribute name' do
    expect { described_class.new(xml, selector: 'time') }.not_to raise_error
  end

  it 'accepts omitted selector' do
    expect { described_class.new(xml, attribute: 'datetime') }.not_to raise_error
  end

  describe '.schema_export' do
    it 'exports the attribute extractor schema', :aggregate_failures do
      expect(described_class.schema_export).to eq(
        type: 'string', const: 'attribute', title: 'attribute',
        description: described_class::DESCRIPTION, examples: ['attribute']
      )
    end
  end
end
