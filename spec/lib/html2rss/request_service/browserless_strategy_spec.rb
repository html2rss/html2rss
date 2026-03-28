# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

RSpec.describe Html2rss::RequestService::BrowserlessStrategy do
  subject(:instance) { described_class.new(ctx) }

  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      total_timeout_seconds: 30,
      validate_request!: nil
    )
  end
  let(:budget) { instance_double(Html2rss::RequestService::Budget, consume!: nil) }
  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com', policy:, budget:) }

  describe '#execute' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:response) { instance_double(Html2rss::RequestService::Response) }
    let(:commander) { instance_double(Html2rss::RequestService::PuppetCommander, call: response) }
    let(:browser) { instance_double(Puppeteer::Browser, disconnect: nil) }

    before do
      allow(Puppeteer).to receive(:connect).and_yield(browser)
      allow(Html2rss::RequestService::PuppetCommander).to receive(:new).with(ctx, browser).and_return(commander)
    end

    it 'calls PuppetCommander', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect { instance.execute }.not_to raise_error

      expect(budget).to have_received(:consume!)
      expect(policy).to have_received(:validate_request!).with(
        url: ctx.url,
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(Puppeteer).to have_received(:connect).with(
        browser_ws_endpoint: instance.browser_ws_endpoint,
        protocol_timeout: 30_000
      )
      expect(commander).to have_received(:call)
    end

    it 'maps Puppeteer timeout errors to RequestTimedOut' do
      allow(commander).to receive(:call).and_raise(Puppeteer::TimeoutError.new('Navigation timeout'))

      expect do
        instance.execute
      end.to raise_error(Html2rss::RequestService::RequestTimedOut, 'Navigation timeout')
    end

    it 'retries without protocol timeout when Puppeteer does not support it', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Puppeteer).to receive(:connect)
        .with(browser_ws_endpoint: instance.browser_ws_endpoint, protocol_timeout: 30_000)
        .and_raise(ArgumentError, 'unknown keyword: :protocol_timeout')
      allow(Puppeteer).to receive(:connect)
        .with(browser_ws_endpoint: instance.browser_ws_endpoint)
        .and_yield(browser)

      expect { instance.execute }.not_to raise_error

      expect(Puppeteer).to have_received(:connect).with(browser_ws_endpoint: instance.browser_ws_endpoint)
      expect(commander).to have_received(:call)
    end

    it 'surfaces actionable diagnostics when Browserless connection fails' do # rubocop:disable RSpec/ExampleLength
      allow(Puppeteer).to receive(:connect)
        .with(browser_ws_endpoint: instance.browser_ws_endpoint, protocol_timeout: 30_000)
        .and_raise(SocketError, 'getaddrinfo: Name or service not known')

      expect do
        instance.execute
      end.to raise_error(
        Html2rss::RequestService::BrowserlessConnectionFailed,
        /Check BROWSERLESS_IO_WEBSOCKET_URL/
      )
    end

    it 'surfaces retry failure details when protocol-timeout compatibility fallback also fails', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Puppeteer).to receive(:connect)
        .with(browser_ws_endpoint: instance.browser_ws_endpoint, protocol_timeout: 30_000)
        .and_raise(ArgumentError, 'unknown keyword: :protocol_timeout')
      allow(Puppeteer).to receive(:connect)
        .with(browser_ws_endpoint: instance.browser_ws_endpoint)
        .and_raise(StandardError, 'Connection refused')

      expect { instance.execute }.to raise_error(Html2rss::RequestService::BrowserlessConnectionFailed) { |error|
        expect(error.message).to include('Connection refused')
        expect(error.message).not_to include('unknown keyword: :protocol_timeout')
      }
    end
  end

  describe '#browser_ws_endpoint' do
    context 'without specified ENV vars' do
      it do
        expect(instance.browser_ws_endpoint).to eq 'ws://127.0.0.1:3000?token=6R0W53R135510'
      end
    end

    context 'with specified ENV vars' do
      around do |example|
        ClimateControl.modify(
          BROWSERLESS_IO_API_TOKEN: 'foobar',
          BROWSERLESS_IO_WEBSOCKET_URL: 'wss://host.tld'
        ) { example.run }
      end

      it do
        expect(instance.browser_ws_endpoint).to eq 'wss://host.tld?token=foobar'
      end
    end

    context 'with a custom websocket URL but no API token' do
      around do |example|
        ClimateControl.modify(
          BROWSERLESS_IO_API_TOKEN: nil,
          BROWSERLESS_IO_WEBSOCKET_URL: 'wss://host.tld'
        ) { example.run }
      end

      it 'raises a clear error' do # rubocop:disable RSpec/ExampleLength
        expect do
          instance.browser_ws_endpoint
        end.to raise_error(
          Html2rss::RequestService::BrowserlessConfigurationError,
          /BROWSERLESS_IO_API_TOKEN is required for custom Browserless endpoints/
        )
      end
    end
  end
end
