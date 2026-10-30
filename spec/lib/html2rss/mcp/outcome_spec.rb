# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Outcome do
  describe Html2rss::MCP::Outcome::NextStep do
    it 'exposes the closed set of wire names from Playbook guidance' do
      expect(described_class::ALL.keys.map(&:to_s)).to contain_exactly(
        'done', 'inspect', 'recon', 'validate', 'apply',
        'scrape', 'capture', 'read_runtime', 'test'
      )
    end

    it 'cannot be built with an unknown name' do
      expect { described_class[:retry_invalid] }
        .to raise_error(ArgumentError, /unknown next_step/)
    end

    it 'owns guidance copy on each named instance' do
      expect(described_class[:inspect].guidance).to include('inspect')
    end
  end

  describe Html2rss::MCP::Outcome::Playbook do
    it 'owns server instructions with bare verb tool names', :aggregate_failures do
      expect(described_class.instructions).to include('→ scrape').and include('→ capture → test → apply')
      expect(described_class.instructions).not_to include('scrape_url')
    end

    it 'embeds auto strategy guidance in scrape_webpage_prompt' do
      prompt = described_class.scrape_webpage_prompt('https://example.com')

      expect(prompt).to include('https://example.com', 'strategy auto', 'payload.items')
    end

    it 'embeds evidence-based enhance guidance in capture_feed_config_prompt' do
      prompt = described_class.capture_feed_config_prompt('https://example.com')

      expect(prompt).to include('suggested_channel_url', 'enhance defaults from admission evidence')
    end

    describe '.inspect_guidance' do
      it 'returns default inspect guidance when articles are present' do
        populated = Html2rss::PageRecon::Diagnostics::Report.new(
          data: { articles_count: 3, alternate_feeds: [] }
        )

        expect(described_class.inspect_guidance(populated))
          .to eq(described_class::GUIDANCE.fetch(:inspect))
      end

      it 'guides blocked surfaces toward botasaurus' do
        expect(described_class.inspect_guidance(report(blocked_surface: true)))
          .to include('anti-bot interstitial')
      end

      it 'guides blocked_surface category toward botasaurus' do
        expect(described_class.inspect_guidance(report(surface_category: 'blocked_surface')))
          .to include('inspect --deep')
      end

      it 'guides js shells toward auto or --deep' do
        expect(described_class.inspect_guidance(report(likely_js_shell: true)))
          .to include('JS-rendered shell')
      end

      it 'guides empty static pages toward redirect verification' do
        expect(described_class.inspect_guidance(report)).to include('redirect_summary.final_url')
      end
    end

    describe '.recon_guidance' do
      it 'appends scheme downgrade hint' do
        result = instance_double(Html2rss::Recon::Result, scheme_downgrade: true)
        next_step = Html2rss::MCP::Outcome::NextStep[:capture]

        expect(described_class.recon_guidance(result, next_step))
          .to include('HTTPS→HTTP downgrade', next_step.guidance)
      end

      it 'returns next_step guidance when scheme is not downgraded' do
        result = instance_double(Html2rss::Recon::Result, scheme_downgrade: false)
        next_step = Html2rss::MCP::Outcome::NextStep[:capture]

        expect(described_class.recon_guidance(result, next_step)).to eq(next_step.guidance)
      end
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

  describe '.inspect_report' do
    it 'points at recon when alternates are present' do
      outcome = described_class.inspect_report(
        report: report(alternate_feeds: [{ href: 'https://example.com/feed.xml' }])
      )

      expect(outcome).to have_attributes(ok: true, next_step: have_attributes(name: :recon))
    end

    it 'points at capture when extractable articles are present' do
      outcome = described_class.inspect_report(report: report(articles_count: 3))

      expect(outcome.next_step.name).to eq(:capture)
    end

    it 'points at scrape when recon is otherwise empty' do
      outcome = described_class.inspect_report(report: report(articles_count: 0))

      expect(outcome.next_step.name).to eq(:scrape)
    end
  end

  describe '.recon' do
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

    it 'emits only the base payload keys when no optional draft fields are given', :aggregate_failures do
      outcome = described_class.capture(**base)

      expect(outcome.payload).to eq(
        yaml: base[:yaml], articles_count: 3, has_selectors: true,
        channel_title: 'Example', requested_strategy: 'auto'
      )
    end

    it 'emits every optional draft field with its wire form when given', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- full wire payload
      outcome = described_class.capture(
        **base, requested_strategy: :auto, segment_strategy: :rss, selected_strategy: 'html',
                admission_drops: { 'credit' => 1 }, native_feed: 'https://example.com/feed.xml',
                suggested_channel_url: 'https://example.com/'
      )

      expect(outcome.payload).to eq(
        yaml: base[:yaml], articles_count: 3, has_selectors: true, channel_title: 'Example',
        requested_strategy: 'auto', segment_strategy: 'rss', selected_strategy: 'html',
        admission_drops: { 'credit' => 1 }, native_feed: 'https://example.com/feed.xml',
        suggested_channel_url: 'https://example.com/'
      )
    end

    it 'keeps the draft ok and points at test when native_feed is absent', :aggregate_failures do
      outcome = described_class.capture(**base, articles_count: 1, has_selectors: true)

      expect(outcome).to have_attributes(ok: true, guidance: described_class::NextStep[:test].guidance)
    end
  end

  describe 'batch verbs' do
    {
      batch_scrape: :scrape, batch_inspect: :inspect, batch_recon: :recon
    }.each do |verb, failure_step|
      describe ".#{verb}" do
        let(:results) { [{ ok: true }, { ok: false }] }

        it 'points at done and echoes the batch wire payload when any item succeeded', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- wire payload
          batch = Html2rss::Batch::BatchResult.new(total: 2, successful: 1, results:)
          outcome = described_class.public_send(verb, batch)

          expect(outcome.ok).to be(true)
          expect(outcome.next_step.name).to eq(:done)
          expect(outcome.guidance).to eq(described_class::NextStep[:done].guidance)
          expect(outcome.payload).to eq(batch.to_h)
        end

        it "points at #{failure_step} when no item succeeded", :aggregate_failures do
          batch = Html2rss::Batch::BatchResult.new(total: 2, successful: 0, results:)
          outcome = described_class.public_send(verb, batch)

          expect(outcome.ok).to be(true)
          expect(outcome.next_step.name).to eq(failure_step)
          expect(outcome.guidance).to eq(described_class::NextStep[failure_step].guidance)
        end
      end
    end
  end

  describe 'test guidance' do
    let(:warned) do
      Html2rss::Test::QualityReport.new(warnings: %w[thin_titles dup_urls], metrics: {}, native_feed: nil,
                                        defer_reason: nil)
    end

    it 'uses the apply guidance on success without warnings' do
      outcome = described_class.test(test_result(success: true))

      expect(outcome.guidance).to eq(described_class::NextStep[:apply].guidance)
    end

    it 'appends quality warnings to the apply guidance on success', :aggregate_failures do
      outcome = described_class.test(test_result(success: true, quality_report: warned))

      expect(outcome.guidance).to eq(
        "#{described_class::NextStep[:apply].guidance} Review payload.quality_report warnings: thin_titles, dup_urls."
      )
      expect(outcome.payload[:quality_report]).to include(warnings: %w[thin_titles dup_urls])
    end

    it 'uses the test error message as guidance on failure' do
      outcome = described_class.test(test_result(error_message: 'Feed is empty'))

      expect(outcome.guidance).to eq('Feed is empty')
    end

    it 'falls back to the next_step guidance when the failure carries no message' do
      outcome = described_class.test(test_result.with(error_message: nil))

      expect(outcome.guidance).to eq(described_class::NextStep[:capture].guidance)
    end
  end

  describe '.validate' do
    it 'points at test with an empty payload on schema success', :aggregate_failures do
      outcome = described_class.validate(report: Html2rss::Config::ValidationReport.ok)

      expect(outcome.ok).to be(true)
      expect(outcome.next_step.name).to eq(:test)
      expect(outcome.payload).to eq({})
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'stays on validate when schema issues are present', :aggregate_failures do
      issue = Html2rss::Config::ValidationIssue.new(
        path: %i[channel], code: :missing_key, message: 'is missing'
      )
      report = Html2rss::Config::ValidationReport.failure([issue])
      outcome = described_class.validate(report:)

      expect(outcome.ok).to be(false)
      expect(outcome.next_step.name).to eq(:validate)
      expect(outcome.payload).to eq(issues: [issue.to_h])
    end
  end

  describe '.test' do
    it 'points at apply on success' do
      expect(described_class.test(test_result(success: true)).next_step.name).to eq(:apply)
    end

    it 'points at validate on schema failure' do # rubocop:disable RSpec/ExampleLength
      result = test_result(
        failure_kind: Html2rss::Test::FailureKind[:schema],
        validation_issues: [
          Html2rss::Config::ValidationIssue.new(path: %i[channel], code: :missing_key, message: 'missing')
        ],
        error_message: 'Configuration schema validation failed'
      )
      expect(described_class.test(result).next_step.name).to eq(:validate)
    end

    it 'points at capture on execution failure' do
      result = test_result(failure_kind: Html2rss::Test::FailureKind[:execution])
      expect(described_class.test(result).next_step.name).to eq(:capture)
    end

    it 'points at capture on min_items failure' do
      result = test_result(failure_kind: Html2rss::Test::FailureKind[:min_items])
      expect(described_class.test(result).next_step.name).to eq(:capture)
    end

    it 'points at capture on quality failure' do
      result = test_result(failure_kind: Html2rss::Test::FailureKind[:quality])
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

    it 'is not ok when the ship gate reports empty even with items', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 3, empty: true)

      expect(outcome).to have_attributes(ok: false, next_step: have_attributes(name: :inspect))
      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 3)
    end

    it 'includes quality_report in the payload only when given', :aggregate_failures do
      outcome = described_class.apply(rss: '<rss/>', item_count: 1, quality_report: { warnings: [] })

      expect(outcome.payload).to eq(rss: '<rss/>', item_count: 1, quality_report: { warnings: [] })
    end
  end

  describe '#initialize' do
    let(:done) { described_class::NextStep[:done] }

    it 'rejects a next_step that is not a NextStep' do
      expect { described_class.new(ok: true, next_step: :done, guidance: 'g', payload: {}) }
        .to raise_error(ArgumentError, 'next_step must be a NextStep')
    end

    it 'rejects a payload that is not a Hash' do
      expect { described_class.new(ok: true, next_step: done, guidance: 'g', payload: []) }
        .to raise_error(ArgumentError, 'payload must be a Hash')
    end

    it 'coerces ok to a boolean and freezes a copy of the payload', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- envelope invariants
      source = { a: 1 }
      outcome = described_class.new(ok: 'yes', next_step: done, guidance: :hint, payload: source)

      expect(outcome).to have_attributes(ok: true, guidance: 'hint')
      expect(outcome.guidance).to be_frozen
      expect(outcome.payload).to be_frozen
      expect(source).not_to be_frozen
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

    it 'maps ArgumentError without the XOR message to inspect' do
      outcome = described_class.from_error(ArgumentError.new('something else'))

      expect(outcome.next_step.name).to eq(:inspect)
    end

    it 'maps InvalidOption from the MCP edge to the default inspect step', :aggregate_failures do
      outcome = described_class.from_error(Html2rss::InvalidOption.new('config must be a Hash, got String'))

      expect(outcome.next_step.name).to eq(:inspect)
      expect(outcome.payload).to eq(class: 'Html2rss::InvalidOption', message: 'config must be a Hash, got String')
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
