# frozen_string_literal: true

RSpec.describe Html2rss::Recon::Verdict do
  it 'rejects unknown names' do
    expect { described_class.coerce(:maybe) }.to raise_error(ArgumentError, /unknown verdict/)
  end

  it 'exposes closed predicates', :aggregate_failures do
    expect(described_class.coerce(:defer).defer?).to be(true)
    expect(described_class.coerce(:drop).drop?).to be(true)
  end
end
