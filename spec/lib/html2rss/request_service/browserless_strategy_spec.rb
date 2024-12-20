# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

RSpec.describe Html2rss::RequestService::BrowserlessStrategy do
  subject(:instance) { described_class.new(ctx) }

  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com') }

  describe '#execute' do
    let(:response) { instance_double(Html2rss::RequestService::Response) }
    let(:commander) { instance_double(Html2rss::RequestService::PuppetCommander, call: response) }

    before do
      browser = instance_double(Puppeteer::Browser, disconnect: nil)

      allow(Puppeteer).to receive(:connect).and_yield(browser)
      allow(Html2rss::RequestService::PuppetCommander).to receive(:new).with(ctx, browser).and_return(commander)
    end

    it 'calls PuppetCommander', :aggregate_failures do
      expect { instance.execute }.not_to raise_error

      expect(Puppeteer).to have_received(:connect)
      expect(commander).to have_received(:call)
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
  end
end
