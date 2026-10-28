# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SurfaceCategory do
  it 'rejects unknown names' do
    expect { described_class[:maybe] }.to raise_error(ArgumentError, 'unknown surface category: :maybe')
  end

  it 'looks up symbols and strings', :aggregate_failures do
    expect(described_class[:app_shell]).to be_weak
    expect(described_class['listing']).to be_listing_bonus
  end

  it 'marks hub/shell surfaces as weak', :aggregate_failures do
    expect(described_class[:app_shell]).to be_weak
    expect(described_class[:high_entropy_surface]).to be_weak
    expect(described_class[:unsupported_surface]).to be_weak
  end

  it 'marks blocked separately from weak', :aggregate_failures do
    blocked = described_class[:blocked_surface]
    expect(blocked).to be_blocked
    expect(blocked).not_to be_weak
    expect(blocked).not_to be_listing_bonus
  end

  it 'grants listing bonus to the listing surface' do
    expect(described_class[:listing]).to be_listing_bonus
  end

  it 'does not treat listing as blocked' do
    expect(described_class[:listing]).not_to be_blocked
  end

  it 'exposes the surface name as a string and a symbol', :aggregate_failures do
    listing = described_class[:listing]

    expect(listing.to_s).to eq('listing')
    expect(listing.to_sym).to eq(:listing)
  end
end
