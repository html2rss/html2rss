# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::AutoStrategy do
  subject(:execute) { described_class.new(ctx).execute }

  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com') }
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: '<html>ok</html>',
      url: Html2rss::Url.from_absolute('https://example.com'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  it 'falls back to the next strategy and pins the winner', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    allow(Html2rss::RequestService).to receive(:execute)
      .with(ctx, strategy: :faraday)
      .and_raise(Html2rss::RequestService::RequestTimedOut, 'Timed out')
    allow(Html2rss::RequestService).to receive(:execute)
      .with(ctx, strategy: :botasaurus)
      .and_return(response)

    expect(execute).to eq(response)
    expect(ctx.selected_strategy).to eq(:botasaurus)
    expect(Html2rss::RequestService).to have_received(:execute).with(ctx, strategy: :faraday).once
    expect(Html2rss::RequestService).to have_received(:execute).with(ctx, strategy: :botasaurus).once
  end

  it 'reuses pinned strategy without retrying the chain', :aggregate_failures do
    ctx.selected_strategy = :browserless
    allow(Html2rss::RequestService).to receive(:execute).with(ctx, strategy: :browserless).and_return(response)

    expect(execute).to eq(response)
    expect(Html2rss::RequestService).to have_received(:execute).with(ctx, strategy: :browserless).once
    expect(Html2rss::RequestService).not_to have_received(:execute).with(ctx, strategy: :faraday)
  end

  it 'does not swallow non-fallback errors', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    allow(Html2rss::RequestService).to receive(:execute)
      .with(ctx, strategy: :faraday)
      .and_raise(Html2rss::RequestService::PrivateNetworkDenied, 'denied')

    expect { execute }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, 'denied')
    expect(Html2rss::RequestService).to have_received(:execute).with(ctx, strategy: :faraday).once
    expect(Html2rss::RequestService).not_to have_received(:execute).with(ctx, strategy: :botasaurus)
  end

  it 'raises the final failure when all strategies fail' do # rubocop:disable RSpec/ExampleLength
    allow(Html2rss::RequestService).to receive(:execute)
      .with(ctx, strategy: :faraday)
      .and_raise(Html2rss::RequestService::RequestTimedOut, 'Timed out')
    allow(Html2rss::RequestService).to receive(:execute)
      .with(ctx, strategy: :botasaurus)
      .and_raise(Html2rss::RequestService::BotasaurusConnectionFailed, 'bota down')
    allow(Html2rss::RequestService).to receive(:execute)
      .with(ctx, strategy: :browserless)
      .and_raise(Html2rss::RequestService::BrowserlessConnectionFailed, 'browserless down')

    expect { execute }
      .to raise_error(Html2rss::RequestService::BrowserlessConnectionFailed, 'browserless down')
  end
end
