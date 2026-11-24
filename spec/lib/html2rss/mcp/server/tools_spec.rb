# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Server::Tools do
  describe 'batch tool keyword defaults' do
    let(:batch_result) { Html2rss::Batch::BatchResult.new(total: 1, successful: 1, results: []) }
    let(:tools_by_name) { described_class::TOOLS.to_h { |tool| [tool.name, tool] } }

    before do
      allow(Html2rss::Batch).to receive_messages(
        batch_scrape: batch_result, batch_inspect: batch_result, batch_recon: batch_result
      )
    end

    it 'forwards batch_scrape default limit and concurrency' do
      tools_by_name.fetch('batch_scrape').call.call(urls: ['https://example.com/a'])

      expect(Html2rss::Batch).to have_received(:batch_scrape).with(
        urls: ['https://example.com/a'], strategy: :auto, limit: 10, concurrency: 5
      )
    end

    it 'forwards batch_inspect default concurrency' do
      tools_by_name.fetch('batch_inspect').call.call(urls: ['https://example.com/a'])

      expect(Html2rss::Batch).to have_received(:batch_inspect).with(
        urls: ['https://example.com/a'], strategy: :auto, concurrency: 5
      )
    end

    it 'forwards batch_recon default concurrency' do
      tools_by_name.fetch('batch_recon').call.call(urls: ['https://example.com/a'])

      expect(Html2rss::Batch).to have_received(:batch_recon).with(
        urls: ['https://example.com/a'], strategy: :auto, concurrency: 5
      )
    end
  end

  describe 'validate tool edge' do
    let(:validate_tool) { described_class::TOOLS.find { |tool| tool.name == 'validate' } }

    it 'raises InvalidOption for a non-Hash config before the schema check' do
      expect { validate_tool.call.call(config: 'channel: {}') }
        .to raise_error(Html2rss::InvalidOption, 'config must be a Hash, got String')
    end
  end

  describe '.apply_outcome' do
    let(:selector) { 'article' }
    let(:config) do
      { channel: { title: 'Example News' }, strategy: :default,
        selectors: { items: { selector:, enhance: false }, title: { selector: 'h1' },
                     url: { selector: 'a', extractor: 'href' } } }
    end
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body><article><a href="/n/item"><h1>Harbor reopens</h1></a></article></body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }, status: 200
      )
    end
    let(:apply) { described_class.apply_outcome(url: 'https://example.com/news', config:) }

    before do
      allow(Html2rss::RequestService).to receive(:execute) do |ctx, **|
        ctx.budget.consume!
        response
      end
    end

    it 'renders the built RSS document and its item count', :aggregate_failures do
      expect(apply).to have_attributes(ok: true, payload: hash_including(item_count: 1))
      expect(apply.payload[:rss]).to include('<title>Harbor reopens</title>', 'https://example.com/n/item')
    end

    it 'fills channel.url from the tool url', :aggregate_failures do
      expect(apply.payload[:rss]).to include('<link>https://example.com/news</link>')
      expect(apply.payload[:quality_report][:warnings]).not_to include('url_mismatch')
    end

    it 'creates the channel when the config has none', :aggregate_failures do
      config.delete(:channel)
      outcome = described_class.apply_outcome(url: 'https://example.com/news', config:)

      expect(outcome).to have_attributes(ok: true)
      expect(outcome.payload[:rss]).to include('Harbor reopens')
    end

    it 'keeps a channel.url the config already carries' do
      config[:channel][:url] = 'https://other.example/news'
      allow(Html2rss).to receive(:apply).and_call_original
      apply

      expect(Html2rss).to have_received(:apply)
        .with(hash_including(channel: hash_including(url: 'https://other.example/news')))
    end

    it 'accepts yaml input', :aggregate_failures do
      yaml = "channel:\n  title: Yaml News\nstrategy: default\nselectors:\n  items:\n    selector: article\n  " \
             "title:\n    selector: h1\n  url:\n    selector: a\n    extractor: href\n"
      outcome = described_class.apply_outcome(url: 'https://example.com/news', yaml:)

      expect(outcome.payload[:rss]).to include('<title>Yaml News</title>', 'Harbor reopens')
    end

    it 'does not mutate the caller config' do
      expect { apply }.not_to(change { config.dig(:channel, :url) })
    end

    context 'when the selectors match nothing' do
      let(:selector) { 'section' }

      it 'fails the ship gate with a zero item count', :aggregate_failures do
        expect(apply).to have_attributes(ok: false, payload: hash_including(item_count: 0))
      end
    end
  end

  describe '.apply_outcome url_mismatch audit' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- pipeline doubles
    let(:config) { { channel: { title: 'T' }, selectors: { items: { selector: 'a' } } } }
    let(:apply) { described_class.apply_outcome(url: 'https://example.com/news', config:) }
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>', url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }, status: 200
      )
    end
    let(:outcome) do
      Html2rss::FeedPipeline::PipelineOutcome.new(
        response:, articles: [], dedup_dropped: 0, selected_strategy: :default, attempt_count: 0,
        strategy_attempts: [], admission_drops: {}, scrape_target: nil, entry_resolution: nil, feed_channel: nil
      )
    end
    let(:feed_result) do
      status = instance_double(Html2rss::Status, entry_url: 'https://example.com/news', scrape_url:)
      item = instance_double(RSS::Rss::Channel::Item, title: 'Harbor reopens', link: 'https://example.com/a',
                                                      pubDate: nil)
      instance_double(Html2rss::FeedResult, empty?: false, status:,
                                            to_rss: instance_double(RSS::Rss, to_s: '<rss/>', items: [item]))
    end
    let(:scrape_url) { 'https://example.com/news' }

    before do
      allow(Html2rss::FeedPipeline).to receive(:new)
        .and_return(instance_double(Html2rss::FeedPipeline, to_outcome_and_result: [outcome, feed_result]))
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
    end

    it 'is quiet when the scrape landed on the channel url' do
      expect(apply.payload[:quality_report][:warnings]).not_to include('url_mismatch')
    end

    context 'when the scrape landed elsewhere' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherits pipeline doubles
      let(:scrape_url) { 'https://elsewhere.test/page' }

      it 'warns' do
        expect(apply.payload[:quality_report][:warnings]).to include('url_mismatch')
      end
    end
  end

  describe '.apply_outcome ship gate source' do
    let(:config) { { channel: { title: 'T' }, selectors: { items: { selector: 'a' } } } }
    let(:rss) { instance_double(RSS::Rss, to_s: '<rss/>') }

    let(:result_with) do
      lambda do |empty:, item_count:|
        report = instance_double(Html2rss::Test::QualityReport, to_h: {})
        instance_double(Html2rss::Apply::Result, empty?: empty, item_count:, to_rss: rss, quality_report: report)
      end
    end

    it 'follows feed_result.empty?, not the item count', :aggregate_failures do
      allow(Html2rss).to receive(:apply).and_return(result_with.call(empty: true, item_count: 1),
                                                    result_with.call(empty: false, item_count: 0))

      outcomes = Array.new(2) { described_class.apply_outcome(url: 'https://example.com/news', config:) }

      expect(outcomes.map(&:ok)).to eq([false, true])
    end
  end
end
