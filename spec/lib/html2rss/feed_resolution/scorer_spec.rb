# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Scorer do
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

  it 'picks the highest score wherever it appears in the list', :aggregate_failures do
    winner = described_class.pick_winner(
      scored: [
        scored(url: 'https://example.com/b', score: 30, articles_count: 5),
        scored(url: 'https://example.com/a', score: 10, articles_count: 2)
      ],
      entry_articles_count: 1
    )

    expect(winner.url.to_s).to eq('https://example.com/b')
  end

  it 'subtracts the admission drop share of all admitted and dropped items', :aggregate_failures do
    score = described_class.score_assessment(
      assessment(surface_category: :listing, articles_count: 2, admission_drops: { 'junk' => 8 })
    )

    expect(score).to eq(17)
  end

  it 'rejects a winner that only matches the entry article count' do
    winner = described_class.pick_winner(
      scored: [scored(url: 'https://example.com/a', score: 30, articles_count: 3)],
      entry_articles_count: 3
    )

    expect(winner).to be_nil
  end

  it 'rounds the admission drop share to whole points' do
    score = described_class.score_assessment(
      assessment(surface_category: :listing, articles_count: 2, admission_drops: { 'junk' => 1 })
    )

    expect(score).to eq(22)
  end

  it 'returns nil when there are no candidates at all' do
    expect(described_class.pick_winner(scored: [], entry_articles_count: 0)).to be_nil
  end

  it 'scores an empty surface as zero without dividing by zero' do
    score = described_class.score_assessment(assessment(surface_category: :app_shell, articles_count: 0))

    expect(score).to eq(0)
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
