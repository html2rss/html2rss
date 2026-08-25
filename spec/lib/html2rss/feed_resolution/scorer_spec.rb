# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Scorer do
  def assessment(surface_category:, articles_count:, admission_drops: {})
    Html2rss::PageRecon::Assessment.new(
      surface_category:,
      articles_count:,
      admission_drops:,
      html_response: true
    )
  end

  def scored(url:, score:, articles_count:)
    Html2rss::FeedResolution::Probe::Scored.new(
      url: Html2rss::Url.from_absolute(url),
      score:,
      articles_count:
    )
  end

  it 'scores feed item counts linearly' do
    expect(described_class.score_feed(articles_count: 4)).to eq(40)
  end

  it 'adds a listing bonus for non-weak HTML surfaces', :aggregate_failures do
    listing = described_class.score_assessment(
      assessment(surface_category: :listing, articles_count: 3)
    )
    weak = described_class.score_assessment(
      assessment(surface_category: :app_shell, articles_count: 3)
    )

    expect(listing).to be > weak
    expect(weak).to eq(30)
  end

  it 'penalizes high admission drop ratios' do
    penalized = described_class.score_assessment(
      assessment(surface_category: :listing, articles_count: 2, admission_drops: { 'junk' => 8 })
    )
    clean = described_class.score_assessment(
      assessment(surface_category: :listing, articles_count: 2)
    )

    expect(penalized).to be < clean
  end

  it 'picks the highest score that beats the entry article count' do
    winner = described_class.pick_winner(
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
      described_class.pick_winner(
        scored: [scored(url: 'https://example.com/a', score: 10, articles_count: 1)],
        entry_articles_count: 3
      )
    ).to be_nil
  end
end

# rubocop:enable RSpec/ExampleLength
