# frozen_string_literal: true

RSpec.describe Html2rss::Test::FailureKind do
  it 'rejects unknown names' do
    expect { described_class.coerce(:timeout) }.to raise_error(ArgumentError, /unknown failure kind/)
  end

  it 'classifies closed failure kinds', :aggregate_failures do
    expect(described_class.coerce(:schema).schema?).to be(true)
    expect(described_class.coerce(:execution).execution?).to be(true)
    expect(described_class.coerce(:min_items).min_items?).to be(true)
  end
end
