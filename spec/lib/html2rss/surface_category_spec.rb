# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SurfaceCategory do
  it 'marks hub/shell surfaces as weak', :aggregate_failures do
    expect(described_class.coerce(:app_shell)).to be_weak
    expect(described_class.coerce(:high_entropy_surface)).to be_weak
    expect(described_class.coerce(:unsupported_surface)).to be_weak
  end

  it 'marks blocked separately from weak', :aggregate_failures do
    blocked = described_class.coerce(:blocked_surface)
    expect(blocked).to be_blocked
    expect(blocked).not_to be_weak
    expect(blocked).not_to be_listing_bonus
  end

  it 'grants listing bonus to non-weak non-blocked surfaces' do
    expect(described_class.coerce(:listing)).to be_listing_bonus
  end
end
