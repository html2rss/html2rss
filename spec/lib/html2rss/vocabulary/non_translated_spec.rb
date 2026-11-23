# frozen_string_literal: true

RSpec.describe Html2rss::Vocabulary::NonTranslated do
  it 'holds frozen sets of structural and commercial words', :aggregate_failures do
    expect(described_class::STRUCTURAL).to be_frozen.and include('menu', 'sidebar', 'pager')
    expect(described_class::COMMERCIAL).to be_frozen.and include('casino', 'vpn', 'dating')
  end

  it 'joins both groups as PATH', :aggregate_failures do
    expect(described_class::PATH).to be_frozen
    expect(described_class::PATH).to eq(described_class::STRUCTURAL | described_class::COMMERCIAL)
  end

  it 'is not a language' do
    expect(Html2rss::Vocabulary::SHARED_LANGUAGES).not_to include(described_class)
  end
end
