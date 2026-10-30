# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Text do
  subject { described_class.new(xml, **options).call }

  let(:xml) { Nokogiri.HTML('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { { selector: 'p' } }

  it { is_expected.to eq 'Lorem ipsum dolor ...' }

  it 'uses the selector to pick the element' do
    expect(described_class.new(xml, selector: 'b').call).to eq 'ipsum'
  end

  it 'accepts omitted selector' do
    expect { described_class.new(xml) }.not_to raise_error
  end

  context 'with surrounding and repeated whitespace' do
    let(:xml) { Nokogiri.HTML("<p>\n  Lorem\n\n   ipsum \t dolor  \n</p>") }

    it { is_expected.to eq 'Lorem ipsum dolor' }
  end

  describe '.schema_export' do
    it 'exports the text extractor schema', :aggregate_failures do
      expect(described_class.schema_export).to eq(
        type: 'string', const: 'text', title: 'text',
        description: described_class::DESCRIPTION, examples: ['text']
      )
    end
  end
end
