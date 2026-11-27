# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::EntryResolution::Diag do
  let(:result) do
    Html2rss::AutoSource::EntryResolution::Result.new(
      entry_url: 'https://example.com/',
      scrape_url: 'https://example.com/feed.xml',
      applied: true,
      reason: :winner,
      probe_count: 3,
      winner_score: 40,
      response: nil,
      out_of_scope: 0
    )
  end

  it 'copies the tournament outcome from a result', :aggregate_failures do
    diag = described_class.from_result(result)

    expect(diag).to have_attributes(applied: true, probe_count: 3, reason: :winner, winner_score: 40, out_of_scope: 0)
  end

  it 'includes the winner score in its hash when one exists' do
    expect(described_class.from_result(result).to_h).to eq(
      applied: true, probe_count: 3, reason: :winner, winner_score: 40
    )
  end

  it 'omits the winner score from its hash when there is no winner' do
    diag = described_class.new(applied: false, probe_count: 0, reason: :no_candidates, winner_score: nil,
                               out_of_scope: 0)

    expect(diag.to_h).to eq(applied: false, probe_count: 0, reason: :no_candidates)
  end

  it 'reports the skipped out-of-scope count when there is one' do
    diag = described_class.new(applied: false, probe_count: 0, reason: :no_in_scope_winner, winner_score: nil,
                               out_of_scope: 3)

    expect(diag.to_h).to eq(applied: false, probe_count: 0, reason: :no_in_scope_winner, out_of_scope_skipped: 3)
  end
end
