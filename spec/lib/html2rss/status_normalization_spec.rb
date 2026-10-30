# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Status do
  let(:base) { { version: '1.0.0', scraper_tallies: {}, dedup_dropped: 0 } }
  let(:status) do
    described_class.new(
      **base, scraper_tallies: { 'Selectors' => 1 }, dedup_dropped: 2, selected_strategy: :default, attempt_count: 1,
              strategy_attempts: [{ strategy: :default }], admission_drops: { 'credit' => 1 },
              entry_url: 'https://a.test', scrape_url: 'https://b.test', entry_resolution: { applied: true }
    )
  end

  describe '.new counters' do
    it 'accepts the lower bounds', :aggregate_failures do
      built = described_class.new(**base, attempt_count: 1, selected_strategy: :default)

      expect(built.dedup_dropped).to eq(0)
      expect(built.attempt_count).to eq(1)
    end

    it 'rejects non-Integer counters at the edge', :aggregate_failures do
      expect { described_class.new(**base, dedup_dropped: '3') }
        .to raise_error(Html2rss::InvalidOption, 'dedup_dropped must be an Integer in 0.., got "3"')
      expect { described_class.new(**base, attempt_count: 1.5) }
        .to raise_error(Html2rss::InvalidOption, /attempt_count must be an Integer/)
    end

    it 'names the failing selected_strategy invariant', :aggregate_failures do
      expect { described_class.new(**base, selected_strategy: 'default', attempt_count: 1) }
        .to raise_error(ArgumentError, 'selected_strategy must be a Symbol or nil')
      expect { described_class.new(**base, selected_strategy: :default, attempt_count: 0) }
        .to raise_error(ArgumentError, 'attempt_count must be >= 1 when selected_strategy is set')
    end
  end

  describe '.new normalization' do
    it 'freezes a copy of the version string', :aggregate_failures do
      version = +'1.0.0'
      status = described_class.new(**base, version:)

      expect(status.version).to eq('1.0.0').and be_frozen
      expect(status.version).not_to equal(version)
    end

    it 'stringifies and freezes tallies and admission drops', :aggregate_failures do
      status = described_class.new(**base, scraper_tallies: { Selectors: 2 }, admission_drops: { credit: 1 })

      expect(status.scraper_tallies).to eq('Selectors' => 2).and be_frozen
      expect(status.admission_drops).to eq('credit' => 1).and be_frozen
    end

    it 'freezes every strategy attempt', :aggregate_failures do
      status = described_class.new(**base, strategy_attempts: [{ strategy: :default }])

      expect(status.strategy_attempts).to eq([{ strategy: :default }]).and be_frozen
      expect(status.strategy_attempts.first).to be_frozen
    end

    it 'does not freeze the caller hashes' do
      attempt = { strategy: :default }
      described_class.new(**base, strategy_attempts: [attempt])

      expect(attempt).not_to be_frozen
    end

    it 'names the rejected entry_resolution class' do
      expect { described_class.new(**base, entry_resolution: Object.new) }
        .to raise_error(ArgumentError, 'entry_resolution must be a Hash or FeedResolution::Diag, got Object')
    end

    it 'freezes copies of optional url strings', :aggregate_failures do
      entry = +'https://example.com/a'
      built = described_class.new(**base, entry_url: entry, scrape_url: :symbol_url)

      expect(built.entry_url).to eq('https://example.com/a').and be_frozen
      expect(built.entry_url).not_to equal(entry)
      expect(built.scrape_url).to eq('symbol_url').and be_frozen
    end

    it 'leaves absent urls nil' do
      expect(described_class.new(**base).entry_url).to be_nil
    end

    it 'keeps an absent entry_resolution nil and symbolizes a given one', :aggregate_failures do
      expect(described_class.new(**base).entry_resolution).to be_nil
      expect(described_class.new(**base, entry_resolution: { 'applied' => true }).entry_resolution)
        .to eq(applied: true).and be_frozen
    end
  end

  describe '.build' do
    let(:target) { Html2rss::ScrapeTarget.new(entry_url: 'https://example.com/e', effective_url: 'https://example.com/s') }

    it 'defaults every optional member', :aggregate_failures do
      status = described_class.build(articles: [])

      expect(status.to_h).to eq(version: Html2rss::VERSION, dedup_dropped: 0)
      expect(status.strategy_attempts).to eq([])
    end

    it 'maps the scrape target to entry and scrape urls' do
      status = described_class.build(articles: [], scrape_target: target)

      expect([status.entry_url, status.scrape_url]).to eq(%w[https://example.com/e https://example.com/s])
    end

    it 'prefers explicit urls over the scrape target' do
      status = described_class.build(articles: [], scrape_target: target, entry_url: 'https://a.test', scrape_url: 'https://b.test')

      expect([status.entry_url, status.scrape_url]).to eq(%w[https://a.test https://b.test])
    end
  end

  describe '#to_h' do
    it 'reports every optional member when present' do
      expect(status.to_h.keys).to eq(described_class.members)
    end

    it 'keeps version and a zero dedup_dropped but omits other zero or empty members' do
      expect(described_class.new(**base).to_h).to eq(version: '1.0.0', dedup_dropped: 0)
    end
  end

  describe 'Marshal' do
    it 'round-trips every member', :aggregate_failures do
      restored = Marshal.load(Marshal.dump(status))

      expect(restored).to eq(status).and be_frozen
      expect(restored.entry_url).to be_frozen
      expect(restored.entry_resolution).to be_frozen
    end
  end
end
