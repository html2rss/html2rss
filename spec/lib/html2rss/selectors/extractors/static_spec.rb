# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Static do
  subject { described_class.new(nil, **options).call }

  let(:options) { { static: 'Foobar' } }

  it { is_expected.to eq 'Foobar' }

  it 'accepts omitted document argument' do
    expect { described_class.new(static: 'Foobar') }.not_to raise_error
  end

  it 'accepts omitted static value' do
    expect(described_class.new(nil).call).to be_nil
  end

  describe '.schema_export' do
    it 'exports the static extractor schema', :aggregate_failures do
      expect(described_class.schema_export).to eq(
        type: 'string', const: 'static', title: 'static',
        description: described_class::DESCRIPTION, examples: ['static']
      )
    end
  end
end
