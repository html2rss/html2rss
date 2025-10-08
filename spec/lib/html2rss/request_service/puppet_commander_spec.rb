# frozen_string_literal: true

require 'spec_helper'
require 'puppeteer'

RSpec.describe Html2rss::RequestService::PuppetCommander do # rubocop:disable RSpec/MultipleMemoizedHelpers
  subject(:commander) { described_class.new(ctx, browser) }

  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      total_timeout_seconds: 30,
      max_decompressed_bytes: 5_242_880,
      validate_request!: nil,
      validate_redirect!: nil,
      validate_remote_ip!: nil
    )
  end
  let(:ctx) do
    instance_double(
      Html2rss::RequestService::Context,
      url: Html2rss::Url.from_absolute('https://example.com'),
      origin_url: Html2rss::Url.from_absolute('https://example.com'),
      relation: :initial,
      headers: { 'User-Agent' => 'RSpec' },
      policy:,
      browserless_preload: nil
    )
  end
  let(:browser) { instance_double(Puppeteer::Browser, new_page: page) }
  let(:page) { instance_double(Puppeteer::Page) }
  let(:unsafe_headers) do
    {
      'Host' => 'example.com',
      'Connection' => 'keep-alive',
      'Content-Length' => '123',
      'Transfer-Encoding' => 'chunked',
      'User-Agent' => 'RSpec'
    }
  end
  let(:request) do
    instance_double(
      Puppeteer::HTTPRequest,
      navigation_request?: true,
      url: 'https://example.com/articles',
      redirect_chain: [],
      resource_type: 'document'
    )
  end
  let(:response) do
    instance_double(
      Puppeteer::HTTPResponse,
      headers: { 'Content-Type' => 'text/html' },
      status: 200,
      url: 'https://example.com/articles',
      remote_address: instance_double(Puppeteer::HTTPResponse::RemoteAddress, ip: '93.184.216.34'),
      request:
    )
  end
  let(:event_handlers) { {} }

  before do
    allow(page).to receive(:extra_http_headers=)
    allow(page).to receive(:default_navigation_timeout=)
    allow(page).to receive(:default_timeout=)
    allow(page).to receive(:request_interception=)
    allow(page).to receive(:on) do |event, &block|
      event_handlers[event] = block
    end
    allow(page).to receive(:content).and_return('<html></html>')
    allow(page).to receive(:wait_for_timeout)
    allow(page).to receive(:evaluate)
    allow(page).to receive(:query_selector).and_return(nil)
    allow(page).to receive(:goto).and_return(response)
    allow(page).to receive(:close)
    allow(request).to receive(:continue)
    allow(request).to receive(:abort)
  end

  describe '#call' do
    let(:html_body) { +'<html></html>' }

    before do
      allow(page).to receive(:content) { html_body }
    end

    it 'returns a Response with the correct body and headers', :aggregate_failures do
      result = commander.call

      expect(result.body).to eq('<html></html>')
      expect(result.headers).to eq({ 'Content-Type' => 'text/html' })
      expect(result.status).to eq(200)
      expect(policy).to have_received(:validate_remote_ip!).with(
        ip: '93.184.216.34',
        url: Html2rss::Url.from_absolute('https://example.com/articles')
      )
    end

    it 'closes the page after execution' do
      commander.call

      expect(page).to have_received(:close)
    end

    context 'with preload wait for network idle' do
      before do
        allow(ctx).to receive(:browserless_preload).and_return({ wait_for_network_idle: { timeout_ms: 1_000 } })
      end

      it 'waits for network idle before collecting the body' do
        commander.call

        expect(page).to have_received(:wait_for_timeout).with(1_000).twice
      end
    end

    context 'with preload click selectors' do
      let(:element) { instance_double(Puppeteer::ElementHandle) }

      before do
        allow(ctx).to receive(:browserless_preload).and_return(
          click_selectors: [
            { selector: '.load-more', max_clicks: 3, delay_ms: 0, wait_for_network_idle: { timeout_ms: 200 } }
          ]
        )

        allow(page).to receive(:query_selector).with('.load-more').and_return(element, element, nil)

        load_count = 0
        allow(element).to receive(:click) do
          load_count += 1
          html_body.replace(%(<html data-loads="#{load_count}"></html>))
        end
      end

      it 'clicks until the selector is gone', :aggregate_failures do
        result = commander.call

        expect(page).to have_received(:query_selector).with('.load-more').exactly(3).times
        expect(element).to have_received(:click).twice
        expect(page).to have_received(:wait_for_timeout).with(200).twice
        expect(result.body).to eq('<html data-loads="2"></html>')
      end
    end

    context 'with preload scroll down' do
      before do
        allow(ctx).to receive(:browserless_preload).and_return(
          scroll_down: { iterations: 5, wait_for_network_idle: { timeout_ms: 150 } }
        )

        scroll_heights = [1_000, 2_000, 2_000]
        scroll_calls = 0

        allow(page).to receive(:evaluate) do |script|
          case script
          when '() => window.scrollTo(0, document.body.scrollHeight)'
            scroll_calls += 1
            html_body.replace(%(<html data-scrolls="#{scroll_calls}"></html>))
          when '() => document.body.scrollHeight'
            scroll_heights.shift
          end
        end
      end

      it 'scrolls until content height stabilizes', :aggregate_failures do
        result = commander.call

        expect(page).to have_received(:evaluate)
          .with('() => window.scrollTo(0, document.body.scrollHeight)').exactly(3).times
        expect(page).to have_received(:wait_for_timeout).with(150).exactly(3).times
        expect(result.body).to eq('<html data-scrolls="3"></html>')
      end
    end
  end

  describe '#new_page' do
    it 'sets extra HTTP headers on the page' do
      commander.new_page

      expect(page).to have_received(:extra_http_headers=).with(ctx.headers)
    end

    it 'strips transport headers that Chromium rejects' do
      allow(ctx).to receive(:headers).and_return(unsafe_headers)

      commander.new_page

      expect(page).to have_received(:extra_http_headers=).with('User-Agent' => 'RSpec')
    end

    it 'sets page timeouts from the request policy', :aggregate_failures do
      commander.new_page

      expect(page).to have_received(:default_navigation_timeout=).with(30_000)
      expect(page).to have_received(:default_timeout=).with(30_000)
    end

    it 'sets up request interception and response guards', :aggregate_failures do
      commander.new_page

      expect(page).to have_received(:request_interception=).with(true)
      expect(page).to have_received(:on).with('request')
      expect(page).to have_received(:on).with('response')
    end
  end

  describe 'navigation guards' do
    before { commander.new_page }

    it 'validates each navigation request before continuing', :aggregate_failures do
      event_handlers.fetch('request').call(request)

      expect(policy).to have_received(:validate_request!).with(
        url: Html2rss::Url.from_absolute('https://example.com/articles'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(request).to have_received(:continue)
    end

    it 'validates redirect hops from the request chain' do
      redirect_request = instance_double(Puppeteer::HTTPRequest, url: 'https://example.com/redirect')
      allow(request).to receive_messages(
        url: 'https://example.com/final',
        redirect_chain: [redirect_request]
      )

      event_handlers.fetch('request').call(request)

      expect(policy).to have_received(:validate_redirect!).with(
        from_url: Html2rss::Url.from_absolute('https://example.com/redirect'),
        to_url: Html2rss::Url.from_absolute('https://example.com/final'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
    end

    it 'aborts skipped resources without validating navigation policy', :aggregate_failures do
      asset_request = instance_double(
        Puppeteer::HTTPRequest,
        navigation_request?: false,
        url: 'https://example.com/image.png',
        redirect_chain: [],
        resource_type: 'image'
      )
      allow(asset_request).to receive(:abort)

      event_handlers.fetch('request').call(asset_request)

      expect(asset_request).to have_received(:abort)
      expect(policy).to have_received(:validate_request!).with(
        url: Html2rss::Url.from_absolute('https://example.com/image.png'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
    end

    it 'aborts denied non-navigation requests without continuing them', :aggregate_failures do
      asset_request = instance_double(
        Puppeteer::HTTPRequest,
        navigation_request?: false,
        url: 'https://127.0.0.1/private',
        redirect_chain: [],
        resource_type: 'fetch'
      )
      error = Html2rss::RequestService::PrivateNetworkDenied.new('blocked')

      allow(asset_request).to receive(:continue)
      allow(asset_request).to receive(:abort)
      allow(policy).to receive(:validate_request!).and_raise(error)

      event_handlers.fetch('request').call(asset_request)

      expect(policy).to have_received(:validate_request!).with(
        url: Html2rss::Url.from_absolute('https://127.0.0.1/private'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(asset_request).to have_received(:abort)
      expect(asset_request).not_to have_received(:continue)
    end

    it 'raises stored navigation policy errors from goto', :aggregate_failures do
      error = Html2rss::RequestService::PrivateNetworkDenied.new('blocked')
      allow(policy).to receive(:validate_request!).and_raise(error)
      allow(page).to receive(:goto) do
        event_handlers.fetch('request').call(request)
        response
      end

      expect do
        commander.navigate_to_destination(page, ctx.url)
      end.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, 'blocked')
      expect(request).to have_received(:abort)
    end
  end

  describe '#navigate_to_destination' do
    it 'navigates to the given URL' do
      commander.navigate_to_destination(page, ctx.url)

      expect(page).to have_received(:goto).with(
        ctx.url,
        wait_until: 'networkidle0',
        referer: 'https://example.com',
        timeout: 30_000
      )
    end
  end

  describe '#body' do
    it 'returns the content of the page' do
      allow(page).to receive(:content).and_return('<html></html>')

      result = commander.body(page)

      expect(result).to eq('<html></html>')
    end
  end
end
