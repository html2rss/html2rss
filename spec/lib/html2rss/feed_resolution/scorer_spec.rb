# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Scorer do
  let(:base_recon) do
    {
      requested_url: 'https://example.com/',
      final_url: 'https://example.com/news',
      status: 200,
      scheme_downgrade: false,
      alternate_feeds: [],
      segment_stats: nil,
      html_response: true,
      content_type: 'text/html',
      blocked_surface: nil,
      sst: nil
    }
  end

  it 'scores feed item counts linearly' do
    expect(described_class.score_feed(articles_count: 4)).to eq(40)
  end

  it 'adds a listing bonus for non-weak HTML surfaces', :aggregate_failures do
    listing = described_class.score_recon(
      Html2rss::PageRecon::Result.new(**base_recon, surface_category: :listing, articles_count: 3,
                                                    admission_drops: {})
    )
    weak = described_class.score_recon(
      Html2rss::PageRecon::Result.new(**base_recon, surface_category: :app_shell, articles_count: 3,
                                                    admission_drops: {})
    )

    expect(listing).to be > weak
    expect(weak).to eq(30)
  end

  it 'penalizes high admission drop ratios' do
    penalized = described_class.score_recon(
      Html2rss::PageRecon::Result.new(**base_recon, surface_category: :listing, articles_count: 2,
                                                    admission_drops: { 'junk' => 8 })
    )
    clean = described_class.score_recon(
      Html2rss::PageRecon::Result.new(**base_recon, surface_category: :listing, articles_count: 2,
                                                    admission_drops: {})
    )

    expect(penalized).to be < clean
  end
end

# rubocop:enable RSpec/ExampleLength
