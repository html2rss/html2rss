# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Outcome do
  describe Html2rss::MCP::Outcome::NextStep do
    it 'exposes the closed set of wire names' do
      expect(described_class::NAMES.map(&:to_s)).to contain_exactly(
        'done', 'inspect_url', 'validate_config', 'apply_config',
        'scrape_url', 'capture_config', 'read_runtime'
      )
    end

    it 'cannot be built with an unknown name' do
      expect { described_class.new(name: :retry_faraday) }
        .to raise_error(ArgumentError, /unknown next_step/)
    end

    it 'owns guidance copy on each named factory' do
      expect(described_class.inspect_url.guidance).to include('inspect_url')
    end
  end

  describe '.scrape' do
    let(:items) { [{ title: 'A', url: 'https://example.com/a' }] }

    it 'succeeds with next_step done when articles are present', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- payload keys are one story
      outcome = described_class.scrape(
        items:, requested_strategy: :auto, channel_title: 'Channel',
        botasaurus_configured: false
      )

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:done)
      expect(outcome.payload).to include(
        items:, total: 1, requested_strategy: 'auto', channel_title: 'Channel'
      )
      expect(outcome.payload).not_to have_key(:admission_drops)
    end

    it 'keeps ok true and points at inspect_url when empty and Botasaurus is configured' do
      outcome = described_class.scrape(
        items: [], requested_strategy: :auto, channel_title: 'Channel',
        botasaurus_configured: true
      )

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :inspect_url))
    end

    it 'points at read_runtime when empty and Botasaurus is unset' do
      outcome = described_class.scrape(
        items: [], requested_strategy: :auto, channel_title: 'Channel',
        botasaurus_configured: false
      )

      expect(outcome.next_step.name).to eq(:read_runtime)
    end

    it 'includes admission_drops only when present' do
      outcome = described_class.scrape(
        items:, requested_strategy: :auto, channel_title: 'Channel',
        admission_drops: { 'credit' => 1 }, botasaurus_configured: true
      )

      expect(outcome.payload[:admission_drops]).to eq('credit' => 1)
    end
  end

  describe '.inspect' do
    it 'points at done when recon found native alternate feeds' do
      outcome = described_class.inspect(payload: { alternate_feeds: [{ href: 'https://example.com/feed.xml' }] })

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done))
    end

    it 'points at capture_config when recon found extractable articles' do
      outcome = described_class.inspect(payload: { articles_count: 3, alternate_feeds: [] })

      expect(outcome.next_step.name).to eq(:capture_config)
    end

    it 'points at scrape_url when recon is otherwise empty' do
      outcome = described_class.inspect(payload: { articles_count: 0, alternate_feeds: [] })

      expect(outcome.next_step.name).to eq(:scrape_url)
    end
  end

  describe '.capture' do
    let(:base) do
      { yaml: "channel:\n  url: https://example.com\n", articles_count: 3, has_selectors: true,
        channel_title: 'Example', requested_strategy: 'auto' }
    end

    it 'points at validate_config when the draft has articles and selectors' do
      outcome = described_class.capture(**base)

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :validate_config))
    end

    it 'points at inspect_url when articles_count is zero' do
      outcome = described_class.capture(**base, articles_count: 0)

      expect(outcome.next_step.name).to eq(:inspect_url)
    end

    it 'points at inspect_url when selectors are missing' do
      outcome = described_class.capture(**base, has_selectors: false)

      expect(outcome.next_step.name).to eq(:inspect_url)
    end

    it 'puts YAML inside payload rather than as the whole result' do
      outcome = described_class.capture(**base)

      expect(outcome.payload[:yaml]).to include('channel:')
    end
  end

  describe '.validate' do
    it 'points at apply_config with an empty payload on schema success', :aggregate_failures do
      outcome = described_class.validate(errors: nil)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:apply_config)
      expect(outcome.payload).to eq({})
    end

    it 'stays on validate_config when schema errors are present', :aggregate_failures do
      outcome = described_class.validate(errors: { channel: ['is missing'] })

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:validate_config)
      expect(outcome.payload).to eq(errors: { channel: ['is missing'] })
    end
  end

  describe '.apply' do
    it 'points at done when RSS items exist', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 1)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:done)
      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 1)
    end

    it 'is not ok and points at inspect_url when item_count is zero' do
      outcome = described_class.apply(rss: '<rss/>', item_count: 0)

      expect(outcome).to have_attributes(ok: false, next_step: have_attributes(name: :inspect_url))
    end
  end

  describe '.from_error' do
    it 'maps BotasaurusConfigurationError to read_runtime without leaking env', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- class/message only
      error = Html2rss::RequestService::BotasaurusConfigurationError.new('BOTASAURUS_SCRAPER_URL is required')
      outcome = described_class.from_error(error, botasaurus_configured: false)

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:read_runtime)
      expect(outcome.payload).to eq(
        class: 'Html2rss::RequestService::BotasaurusConfigurationError',
        message: 'BOTASAURUS_SCRAPER_URL is required'
      )
      expect(outcome.payload.keys).to contain_exactly(:class, :message)
    end

    it 'maps NoFeedItemsExtracted to inspect_url' do
      error = Html2rss::NoFeedItemsExtracted.new(attempts: [], surface_category: nil)
      outcome = described_class.from_error(error, botasaurus_configured: true)

      expect(outcome.next_step.name).to eq(:inspect_url)
    end

    it 'maps XOR ArgumentError to validate_config' do
      error = ArgumentError.new('Provide exactly one of config or yaml')
      outcome = described_class.from_error(error, botasaurus_configured: true)

      expect(outcome.next_step.name).to eq(:validate_config)
    end

    it 'maps other exceptions to inspect_url' do
      outcome = described_class.from_error(StandardError.new('boom'), botasaurus_configured: true)

      expect(outcome.next_step.name).to eq(:inspect_url)
    end
  end

  describe '#to_h' do
    it 'serializes next_step as a wire string and keeps payload', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- wire shape
      outcome = described_class.apply(rss: '<rss/>', item_count: 2)
      wire = outcome.to_h

      expect(wire).to eq(
        ok: true,
        next_step: 'done',
        guidance: outcome.guidance,
        payload: { rss: '<rss/>', item_count: 2 }
      )
      expect(wire[:next_step]).to be_a(String)
    end
  end
end
