# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Status do
  describe '.build' do
    let(:articles) do
      [
        Html2rss::Article.new(id: '1', title: 'A', url: 'https://example.com/a', scraper: Html2rss::Selectors),
        Html2rss::Article.new(id: '2', title: 'B', url: 'https://example.com/b', scraper: Html2rss::Selectors),
        Html2rss::Article.new(id: '3', title: 'C', url: 'https://example.com/c',
                              scraper: Html2rss::AutoSource::Scraper::Html)
      ]
    end

    it 'records version, scraper tallies, and dedup_dropped', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      status = described_class.build(articles:, dedup_dropped: 2)

      expect(status.version).to eq(Html2rss::VERSION)
      expect(status.scraper_tallies).to eq('Selectors' => 2, 'AutoSource::Html' => 1)
      expect(status.scraper_tallies).to be_frozen
      expect(status.dedup_dropped).to eq(2)
      expect(status.selected_strategy).to be_nil
      expect(status.attempt_count).to eq(0)
    end

    # rubocop:disable RSpec/ExampleLength -- auto summary + to_h + generator non-bloat
    it 'accepts auto strategy summary without putting it in the generator string', :aggregate_failures do
      status = described_class.build(
        articles:,
        dedup_dropped: 0,
        selected_strategy: :botasaurus,
        attempt_count: 2,
        strategy_attempts: [
          { strategy: :faraday, items_count: 0, error_class: nil },
          { strategy: :botasaurus, items_count: 1, error_class: nil,
            transport_meta: { 'request_id' => 'abc', 'render_ms' => 12 } }
        ]
      )

      expect(status.selected_strategy).to eq(:botasaurus)
      expect(status.attempt_count).to eq(2)
      expect(status.strategy_attempts.size).to eq(2)
      expect(status.to_h).to include(selected_strategy: :botasaurus, attempt_count: 2)
      expect(status.to_h[:strategy_attempts].last[:transport_meta]).to include('request_id' => 'abc')
      expect(status.to_generator_comment).not_to include('botasaurus')
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'telemetry invariants' do
    # rubocop:disable RSpec/ExampleLength -- covers the closed invalid-telemetry matrix
    it 'rejects negative counters and inconsistent auto summary', :aggregate_failures do
      expect do
        described_class.new(version: '1', scraper_tallies: {}, dedup_dropped: -1)
      end.to raise_error(ArgumentError, /dedup_dropped/)

      expect do
        described_class.new(version: '1', scraper_tallies: {}, dedup_dropped: 0, attempt_count: -1)
      end.to raise_error(ArgumentError, /attempt_count/)

      expect do
        described_class.new(version: '1', scraper_tallies: {}, dedup_dropped: 0, selected_strategy: 'faraday')
      end.to raise_error(ArgumentError, /selected_strategy/)

      expect do
        described_class.new(version: '1', scraper_tallies: {}, dedup_dropped: 0,
                            selected_strategy: :faraday, attempt_count: 0)
      end.to raise_error(ArgumentError, /attempt_count must be >= 1/)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'defensively copies tallies so callers cannot mutate telemetry', :aggregate_failures do
      tallies = { 'Selectors' => 1 }
      status = described_class.new(version: '1.0.0', scraper_tallies: tallies, dedup_dropped: 0)
      tallies['Selectors'] = 99

      expect(status.scraper_tallies).to eq('Selectors' => 1)
      expect { status.scraper_tallies['Selectors'] = 2 }.to raise_error(FrozenError)
    end

    # rubocop:disable RSpec/ExampleLength -- Marshal freeze contract for tallies + attempts
    it 're-freezes tallies and strategy_attempts after Marshal round-trip', :aggregate_failures do
      status = described_class.build(
        articles: [],
        dedup_dropped: 1,
        strategy_attempts: [{ strategy: :faraday, items_count: 0, error_class: nil }]
      )
      restored = Marshal.load(Marshal.dump(status))

      expect(restored).to be_frozen
      expect(restored.scraper_tallies).to be_frozen
      expect(restored.strategy_attempts).to be_frozen
      expect(restored.strategy_attempts.first).to be_frozen
      expect(restored.dedup_dropped).to eq(1)
      expect(restored.strategy_attempts).to eq([{ strategy: :faraday, items_count: 0, error_class: nil }])
      expect { restored.scraper_tallies['x'] = 1 }.to raise_error(FrozenError)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '#to_h' do
    # rubocop:disable RSpec/ExampleLength -- tallies present for both scraper homes
    it 'includes scraper_tallies for selector and auto-source scrapers', :aggregate_failures do
      status = described_class.build(
        articles: [
          Html2rss::Article.new(id: '1', title: 'A', url: 'https://example.com/a',
                                scraper: Html2rss::AutoSource::Scraper::Html),
          Html2rss::Article.new(id: '2', title: 'B', url: 'https://example.com/b',
                                scraper: Html2rss::Selectors)
        ],
        dedup_dropped: 0
      )

      expect(status.to_h).to include(
        version: Html2rss::VERSION,
        dedup_dropped: 0,
        scraper_tallies: { 'AutoSource::Html' => 1, 'Selectors' => 1 }
      )
      expect(status.to_h).not_to include(:selected_strategy, :attempt_count, :strategy_attempts)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength -- member vs to_h omission contract
    it 'omits scraper_tallies when no article carries a scraper', :aggregate_failures do
      status = described_class.build(
        articles: [Html2rss::Article.new(id: '1', title: 'A', url: 'https://example.com/a')],
        dedup_dropped: 0
      )

      expect(status.scraper_tallies).to eq({})
      expect(status.to_h).to eq(version: Html2rss::VERSION, dedup_dropped: 0)
      expect(status.to_h).not_to have_key(:scraper_tallies)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'omits nil selected_strategy, zero attempt_count, and empty strategy_attempts', :aggregate_failures do
      status = described_class.build(articles: [], dedup_dropped: 3)

      expect(status.selected_strategy).to be_nil
      expect(status.attempt_count).to eq(0)
      expect(status.strategy_attempts).to eq([])
      expect(status.to_h.keys).to contain_exactly(:version, :dedup_dropped)
    end
  end

  describe '#to_generator_comment' do
    # rubocop:disable RSpec/ExampleLength -- setup + exact generator string
    it 'formats the RSS generator / JSON Feed user_comment string' do
      comment = described_class.new(
        version: '9.9.9',
        scraper_tallies: { 'Selectors' => 2, 'AutoSource::Html' => 1 },
        dedup_dropped: 0
      ).to_generator_comment

      expect(comment).to eq('html2rss V. 9.9.9 (scrapers: Selectors (2), AutoSource::Html (1))')
    end
    # rubocop:enable RSpec/ExampleLength

    it 'omits the scrapers clause when tallies are empty', :aggregate_failures do
      comment = described_class.new(version: '9.9.9', scraper_tallies: {}, dedup_dropped: 0)
                               .to_generator_comment

      expect(comment).to eq('html2rss V. 9.9.9')
      expect(comment).not_to include('scrapers:')
    end
  end

  describe 'Marshal vs to_h' do
    # rubocop:disable RSpec/ExampleLength -- round-trip keeps empty member tallies
    it 'restores empty tallies on members even when to_h omitted them', :aggregate_failures do
      status = described_class.build(articles: [], dedup_dropped: 0)
      restored = Marshal.load(Marshal.dump(status))

      expect(status.to_h).not_to have_key(:scraper_tallies)
      expect(restored.scraper_tallies).to eq({})
      expect(restored.attempt_count).to eq(0)
      expect(restored.selected_strategy).to be_nil
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
