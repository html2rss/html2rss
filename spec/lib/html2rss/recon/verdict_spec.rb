# frozen_string_literal: true

RSpec.describe Html2rss::Recon::Verdict do
  it 'rejects unknown names' do
    expect { described_class[:maybe] }.to raise_error(ArgumentError, /unknown verdict/)
  end

  it 'looks up symbols and strings', :aggregate_failures do
    expect(described_class[:defer].defer?).to be(true)
    expect(described_class['drop'].drop?).to be(true)
  end
end
