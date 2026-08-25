# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Policy do
  let(:config) do
    instance_double(Html2rss::Config, auto_source: { entry_resolution: { enabled: true } }, selectors: nil)
  end
  let(:native) { Html2rss::AutoSource::Scraper::NativeFeed }
  let(:schema) { Html2rss::AutoSource::Scraper::Schema }
  let(:schema_article) { instance_double(Html2rss::Article, scraper: schema) }
  let(:native_article) { instance_double(Html2rss::Article, scraper: native) }

  it 'resolves when articles are below the floor' do
    expect(
      described_class.resolve?(config:, articles: [schema_article], surface_category: :listing)
    ).to be true
  end

  it 'skips blocked surfaces' do
    expect(
      described_class.resolve?(config:, articles: [], surface_category: :blocked_surface)
    ).to be false
  end

  it 'skips when selectors are present' do
    config = instance_double(Html2rss::Config, auto_source: { entry_resolution: { enabled: true } },
                                               selectors: { items: {} })
    expect(
      described_class.resolve?(config:, articles: [], surface_category: :unsupported_surface)
    ).to be false
  end

  it 'skips when entry_resolution is disabled' do
    config = instance_double(Html2rss::Config,
                             auto_source: { entry_resolution: { enabled: false } }, selectors: nil)
    expect(
      described_class.resolve?(config:, articles: [], surface_category: :unsupported_surface)
    ).to be false
  end

  it 'skips when ≥3 Schema-only articles on a non-weak surface' do
    articles = [schema_article, schema_article, schema_article]
    expect(
      described_class.resolve?(config:, articles:, surface_category: :listing)
    ).to be false
  end

  it 'resolves when ≥3 NativeFeed articles on a non-weak surface' do
    articles = [native_article, native_article, native_article]
    expect(
      described_class.resolve?(config:, articles:, surface_category: :listing)
    ).to be true
  end

  it 'resolves at integer ≥50% NativeFeed majority (1 of 2)' do
    articles = [native_article, schema_article]
    expect(
      described_class.resolve?(config:, articles:, surface_category: :listing)
    ).to be true
  end

  it 'raises when articles is not an Array' do
    expect do
      described_class.resolve?(config:, articles: nil, surface_category: :listing)
    end.to raise_error(ArgumentError, 'articles must be an Array')
  end
end
