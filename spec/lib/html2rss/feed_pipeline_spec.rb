# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline do
  def build_response(body:, url: 'https://example.com/news')
    Html2rss::RequestService::Response.new(
      body:,
      url: Html2rss::Url.from_absolute(url),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  let(:base_config) do
    {
      channel: { url: 'https://example.com/news', title: 'Example News' },
      selectors: {
        items: { selector: 'article' },
        title: { selector: 'h1' }
      }
    }
  end

  describe '#to_rss' do
    context 'when strategy is non-auto' do
      let(:config) { base_config.merge(strategy: :faraday) }
      let(:pipeline) { described_class.new(config) }
      let(:response) do
        build_response(body: '<html><body><article><h1>faraday</h1></article></body></html>')
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          raise "Unexpected strategy #{strategy}" unless strategy == :faraday

          response
        end
      end

      it 'runs the configured strategy path and does not invoke auto fallback', :aggregate_failures do
        rss = pipeline.to_rss

        expect(rss.items.map(&:title)).to eq(['faraday'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).not_to have_received(:execute).with(anything, strategy: :botasaurus)
      end
    end

    context 'when strategy is auto' do
      let(:config) { base_config.merge(strategy: :auto, request: { max_requests: 3 }) }
      let(:pipeline) { described_class.new(config) }
      let(:empty_response) do
        build_response(body: '<html><body><div>empty</div></body></html>')
      end
      let(:item_response) do
        build_response(body: '<html><body><article><h1>bota</h1></article></body></html>')
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |ctx, strategy:|
          ctx.budget.consume!
          strategy == :faraday ? empty_response : item_response
        end
      end

      it 'uses auto fallback chain when the first strategy yields zero items', :aggregate_failures do
        rss = pipeline.to_rss

        expect(rss.items.map(&:title)).to eq(['bota'])
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :faraday).once
        expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :botasaurus).once
      end
    end
  end
end
