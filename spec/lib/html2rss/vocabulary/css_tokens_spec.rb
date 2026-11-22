# frozen_string_literal: true

RSpec.describe Html2rss::Vocabulary::CssTokens do
  it 'holds frozen sets of lowercase tokens', :aggregate_failures do
    tokens = [described_class::CONTENT, described_class::JUNK]

    expect(tokens).to all(be_a(Set).and(be_frozen))
    expect(tokens.flat_map(&:to_a)).to all(satisfy { _1 == _1.downcase && _1 == _1.strip && !_1.empty? })
  end

  it 'marks article and card words as content, and chrome and commerce words as junk', :aggregate_failures do
    expect(described_class::CONTENT).to include('post', 'card', 'nachrichten', 'ニュース')
    expect(described_class::JUNK).to include('sidebar', 'menu', 'casino', 'vpn', 'dating', 'kategorie', 'tags')
  end

  it 'keeps content words out of junk' do
    expect(described_class::CONTENT & described_class::JUNK).to be_empty
  end
end
