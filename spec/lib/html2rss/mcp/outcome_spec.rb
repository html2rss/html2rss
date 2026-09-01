# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Outcome do
  describe Html2rss::MCP::Outcome::NextStep do
    it 'exposes the closed set of wire names' do
      expect(described_class::NAMES.map(&:to_s)).to contain_exactly(
        'done', 'inspect', 'recon', 'validate', 'apply',
        'scrape', 'capture', 'read_runtime', 'test'
      )
    end

    it 'cannot be built with an unknown name' do
      expect { described_class.new(name: :retry_faraday) }
        .to raise_error(ArgumentError, /unknown next_step/)
    end

    it 'owns guidance copy on each named factory' do
      expect(described_class.inspect.guidance).to include('inspect')
    end
  end

  describe Html2rss::MCP::Outcome::Playbook do
    it 'owns server instructions with bare verb tool names', :aggregate_failures do
      expect(described_class.instructions).to include('→ scrape').and include('→ capture → test → apply')
      expect(described_class.instructions).not_to include('scrape_url')
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

    it 'keeps ok true and points at inspect when empty and Botasaurus is configured' do
      outcome = described_class.scrape(
        items: [], requested_strategy: :auto, channel_title: 'Channel',
        botasaurus_configured: true
      )

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :inspect))
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
    def report(**data)
      Html2rss::PageRecon::Diagnostics::Report.new(
        data: { articles_count: 0, alternate_feeds: [], **data }
      )
    end

    it 'points at recon when alternates are present' do
      outcome = described_class.inspect(
        report: report(alternate_feeds: [{ href: 'https://example.com/feed.xml' }])
      )

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :recon))
    end

    it 'points at capture when extractable articles are present' do
      outcome = described_class.inspect(report: report(articles_count: 3))

      expect(outcome.next_step.name).to eq(:capture)
    end

    it 'points at scrape when recon is otherwise empty' do
      outcome = described_class.inspect(report: report(articles_count: 0))

      expect(outcome.next_step.name).to eq(:scrape)
    end
  end

  describe '.recon' do
    def recon_result(verdict:, **attrs) # rubocop:disable Metrics/MethodLength -- fixture builder for recon Result
      Html2rss::Recon::Result.new(
        requested_url: 'https://example.com',
        final_url: 'https://example.com',
        status: 200,
        verdict: Html2rss::Recon::Verdict.coerce(verdict),
        native_feed: nil,
        surface_category: :article_listing,
        articles_count: 3,
        scheme_downgrade: false,
        notes: [],
        html_bytesize: 1000,
        **attrs
      )
    end

    it 'points at done when verdict is defer (native feed)' do
      outcome = described_class.recon(
        result: recon_result(verdict: :defer, native_feed: 'https://example.com/feed.xml')
      )

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done))
    end

    it 'points at capture when verdict is build' do
      outcome = described_class.recon(result: recon_result(verdict: :build))

      expect(outcome.next_step.name).to eq(:capture)
    end

    it 'points at scrape when verdict is drop' do
      outcome = described_class.recon(result: recon_result(verdict: :drop, articles_count: 0))

      expect(outcome.next_step.name).to eq(:scrape)
    end
  end

  describe '.capture' do
    let(:base) do
      { yaml: "channel:\n  url: https://example.com\n", articles_count: 3, has_selectors: true,
        channel_title: 'Example', requested_strategy: 'auto' }
    end

    it 'points at test when the draft has articles and selectors' do
      outcome = described_class.capture(**base)

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :test))
    end

    it 'points at done when native_feed is detected', :aggregate_failures do
      outcome = described_class.capture(**base, native_feed: 'https://example.com/feed.xml')

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :done))
      expect(outcome.payload[:native_feed]).to eq('https://example.com/feed.xml')
    end

    it 'points at inspect when articles_count is zero' do
      outcome = described_class.capture(**base, articles_count: 0)

      expect(outcome.next_step.name).to eq(:inspect)
    end

    it 'points at inspect when selectors are missing' do
      outcome = described_class.capture(**base, has_selectors: false)

      expect(outcome.next_step.name).to eq(:inspect)
    end

    it 'puts YAML inside payload rather than as the whole result' do
      outcome = described_class.capture(**base)

      expect(outcome.payload[:yaml]).to include('channel:')
    end
  end

  describe '.validate' do
    it 'points at test with an empty payload on schema success', :aggregate_failures do
      outcome = described_class.validate(errors: nil)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:test)
      expect(outcome.payload).to eq({})
    end

    it 'stays on validate when schema errors are present', :aggregate_failures do
      outcome = described_class.validate(errors: { channel: ['is missing'] })

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:validate)
      expect(outcome.payload).to eq(errors: { channel: ['is missing'] })
    end
  end

  describe '.test' do
    def test_result(failure_kind: nil, success: false, **) # rubocop:disable Metrics/MethodLength
      Html2rss::Test::Result.new(
        success:,
        item_count: success ? 2 : 0,
        sample_items: [],
        channel_title: 'Example',
        channel_url: 'https://example.com',
        strategy_used: :faraday,
        duration_seconds: 0.1,
        validation_errors: nil,
        error_message: success ? nil : 'failed',
        failure_kind:,
        rss: success ? '<rss/>' : nil,
        **
      )
    end

    it 'points at apply on success' do
      expect(described_class.test(test_result(success: true)).next_step.name).to eq(:apply)
    end

    it 'points at validate on schema failure' do # rubocop:disable RSpec/ExampleLength
      result = test_result(
        failure_kind: Html2rss::Test::FailureKind.coerce(:schema),
        validation_errors: { channel: ['missing'] },
        error_message: 'Configuration schema validation failed'
      )
      expect(described_class.test(result).next_step.name).to eq(:validate)
    end

    it 'points at capture on execution failure' do
      result = test_result(failure_kind: Html2rss::Test::FailureKind.coerce(:execution))
      expect(described_class.test(result).next_step.name).to eq(:capture)
    end

    it 'points at capture on min_items failure' do
      result = test_result(failure_kind: Html2rss::Test::FailureKind.coerce(:min_items))
      expect(described_class.test(result).next_step.name).to eq(:capture)
    end
  end

  describe '.apply' do
    it 'points at done when RSS items exist', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 1)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:done)
      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 1)
    end

    it 'is not ok and points at inspect when item_count is zero' do
      outcome = described_class.apply(rss: '<rss/>', item_count: 0)

      expect(outcome).to have_attributes(ok: false, next_step: have_attributes(name: :inspect))
    end
  end

  describe '.from_error' do
    it 'maps BotasaurusConfigurationError to read_runtime without leaking env', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- class/message only
      error = Html2rss::RequestService::BotasaurusConfigurationError.new('BOTASAURUS_SCRAPER_URL is required')
      outcome = described_class.from_error(error)

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:read_runtime)
      expect(outcome.payload).to eq(
        class: 'Html2rss::RequestService::BotasaurusConfigurationError',
        message: 'BOTASAURUS_SCRAPER_URL is required'
      )
      expect(outcome.payload.keys).to contain_exactly(:class, :message)
    end

    it 'maps NoFeedItemsExtracted to inspect' do
      error = Html2rss::NoFeedItemsExtracted.new(attempts: [], surface_category: nil)
      outcome = described_class.from_error(error)

      expect(outcome.next_step.name).to eq(:inspect)
    end

    it 'maps XOR ArgumentError to validate' do
      error = ArgumentError.new('Provide exactly one of config or yaml')
      outcome = described_class.from_error(error)

      expect(outcome.next_step.name).to eq(:validate)
    end

    it 'maps UnpublishedRequestError to validate' do
      error = Html2rss::MCP::Contract::UnpublishedRequestError.new('MCP does not accept strategy local_file')
      outcome = described_class.from_error(error)

      expect(outcome.next_step.name).to eq(:validate)
    end

    it 'maps other exceptions to inspect' do
      outcome = described_class.from_error(StandardError.new('boom'))

      expect(outcome.next_step.name).to eq(:inspect)
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
