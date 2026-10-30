# frozen_string_literal: true

RSpec.describe Html2rss::Recon::Verdict do
  it 'rejects unknown names' do
    expect { described_class[:maybe] }.to raise_error(ArgumentError, 'unknown verdict: :maybe')
  end

  it 'looks up symbols and strings to the same instance', :aggregate_failures do
    expect(described_class[:defer]).to equal(described_class['defer'])
    expect(described_class[:build]).to equal(described_class::ALL.fetch(:build))
  end

  it 'answers exactly one predicate per verdict', :aggregate_failures do
    {
      build: [true, false, false],
      defer: [false, true, false],
      drop: [false, false, true]
    }.each do |name, expected|
      verdict = described_class[name]
      expect([verdict.build?, verdict.defer?, verdict.drop?]).to eq(expected)
    end
  end

  it 'converts to its symbol and string name', :aggregate_failures do
    expect(described_class[:drop].to_sym).to eq(:drop)
    expect(described_class[:drop].to_s).to eq('drop')
  end

  it 'cannot be instantiated outside the closed set' do
    expect { described_class.new(name: :other) }.to raise_error(NoMethodError)
  end
end
