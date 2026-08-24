# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Policy do
  def config(auto_source: { entry_resolution: { enabled: true } }, selectors: nil)
    instance_double(Html2rss::Config, auto_source:, selectors:)
  end

  it 'resolves when articles are below the floor on a high-entropy surface' do
    expect(
      described_class.resolve?(
        config:,
        articles_count: 1,
        surface_category: :high_entropy_surface
      )
    ).to be true
  end

  it 'skips blocked surfaces' do
    expect(
      described_class.resolve?(
        config:,
        articles_count: 0,
        surface_category: :blocked_surface
      )
    ).to be false
  end

  it 'skips when selectors are present' do
    expect(
      described_class.resolve?(
        config: config(selectors: { items: {} }),
        articles_count: 0,
        surface_category: :unsupported_surface
      )
    ).to be false
  end

  it 'skips when entry_resolution is disabled' do
    expect(
      described_class.resolve?(
        config: config(auto_source: { entry_resolution: { enabled: false } }),
        articles_count: 0,
        surface_category: :unsupported_surface
      )
    ).to be false
  end
end

# rubocop:enable RSpec/ExampleLength
