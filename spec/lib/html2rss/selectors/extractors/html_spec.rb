# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Html do
  subject { described_class.new(xml, **options).call }

  let(:xml) { Nokogiri.HTML('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { { selector: 'p' } }

  it { is_expected.to eq '<p>Lorem <b>ipsum</b> dolor ...</p>' }

  it 'accepts omitted selector' do
    expect { described_class.new(xml) }.not_to raise_error
  end

  describe 'schema export' do
    it 'exports the html extractor schema', :aggregate_failures do
      expect(Html2rss::Selectors::SchemaExport.for_extractor(name: :html, klass: described_class)).to eq(
        type: 'string', const: 'html', title: 'html',
        description: described_class::DESCRIPTION, examples: ['html']
      )
    end
  end
end
