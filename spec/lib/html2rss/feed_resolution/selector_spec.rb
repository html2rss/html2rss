# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Selector do
  def scored(url:, score:, articles_count:)
    Html2rss::FeedResolution::Probe::Scored.new(
      url: Html2rss::Url.from_absolute(url),
      score:,
      articles_count:
    )
  end

  it 'picks the highest score that beats the entry article count' do
    winner = described_class.call(
      scored: [
        scored(url: 'https://example.com/a', score: 10, articles_count: 2),
        scored(url: 'https://example.com/b', score: 30, articles_count: 5)
      ],
      entry_articles_count: 1
    )

    expect(winner.url.to_s).to eq('https://example.com/b')
  end

  it 'returns nil when no candidate beats the entry count' do
    expect(
      described_class.call(
        scored: [scored(url: 'https://example.com/a', score: 10, articles_count: 1)],
        entry_articles_count: 3
      )
    ).to be_nil
  end
end
