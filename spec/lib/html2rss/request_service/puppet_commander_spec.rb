# frozen_string_literal: true

require 'spec_helper'
require 'puppeteer'

RSpec.describe Html2rss::RequestService::PuppetCommander do # rubocop:disable RSpec/MultipleMemoizedHelpers
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
    instance_double(Html2rss::RequestService::Context,
                    url: Html2rss::Url.from_relative('https://example.com', 'https://example.com'),
                    origin_url: Html2rss::Url.from_relative('https://example.com', 'https://example.com'),
                    relation: :initial,
                    headers: { 'User-Agent' => 'RSpec' },
                    policy:)
  end
  let(:browser) { instance_double(Puppeteer::Browser, new_page: page) }
  let(:page) { instance_double(Puppeteer::Page) }
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
      url: 'https://example.com/articles',
      remote_address: instance_double(Puppeteer::HTTPResponse::RemoteAddress, ip: '93.184.216.34'),
      request:
    )
  end
  let(:puppet_commander) { described_class.new(ctx, browser) }
  let(:event_handlers) { {} }

  before do
    allow(page).to receive(:extra_http_headers=)
    allow(page).to receive(:default_navigation_timeout=)
    allow(page).to receive(:default_timeout=)
    allow(page).to receive(:request_interception=)
    allow(page).to receive(:on) do |event, &block|
      event_handlers[event] = block
    end
    allow(page).to receive_messages(goto: response, content: '<html></html>')
    allow(page).to receive(:close)
    allow(request).to receive(:continue)
    allow(request).to receive(:abort)
  end

  describe '#call' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'returns a Response with the correct body and headers', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      result = puppet_commander.call

      expect(result.body).to eq('<html></html>')
      expect(result.headers).to eq({ 'Content-Type' => 'text/html' })
      expect(policy).to have_received(:validate_remote_ip!).with(
        ip: '93.184.216.34',
        url: Html2rss::Url.from_relative('https://example.com/articles', 'https://example.com/articles')
      )
    end

    it 'closes the page after execution' do
      puppet_commander.call

      expect(page).to have_received(:close)
    end
  end

  describe '#new_page' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'sets extra HTTP headers on the page' do
      puppet_commander.new_page

      expect(page).to have_received(:extra_http_headers=).with(ctx.headers)
    end

    it 'strips transport headers that Chromium rejects' do
      unsafe_headers = {
        'Host' => 'example.com',
        'Connection' => 'keep-alive',
        'Content-Length' => '123',
        'Transfer-Encoding' => 'chunked',
        'User-Agent' => 'RSpec'
      }
      allow(ctx).to receive(:headers).and_return(unsafe_headers)

      puppet_commander.new_page

      expect(page).to have_received(:extra_http_headers=).with('User-Agent' => 'RSpec')
    end

    it 'sets page timeouts from the request policy', :aggregate_failures do
      puppet_commander.new_page

      expect(page).to have_received(:default_navigation_timeout=).with(30_000)
      expect(page).to have_received(:default_timeout=).with(30_000)
    end

    it 'sets up request interception and response guards', :aggregate_failures do
      puppet_commander.new_page

      expect(page).to have_received(:request_interception=).with(true)
      expect(page).to have_received(:on).with('request')
      expect(page).to have_received(:on).with('response')
    end
  end

  describe 'navigation guards' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before { puppet_commander.new_page }

    it 'validates each navigation request before continuing', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      event_handlers.fetch('request').call(request)

      expect(policy).to have_received(:validate_request!).with(
        url: Html2rss::Url.from_relative('https://example.com/articles', 'https://example.com/articles'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(request).to have_received(:continue)
    end

    it 'validates redirect hops from the request chain' do # rubocop:disable RSpec/ExampleLength
      redirect_request = instance_double(Puppeteer::HTTPRequest, url: 'https://example.com/redirect')
      allow(request).to receive_messages(
        url: 'https://example.com/final',
        redirect_chain: [redirect_request]
      )

      event_handlers.fetch('request').call(request)

      expect(policy).to have_received(:validate_redirect!).with(
        from_url: Html2rss::Url.from_relative('https://example.com/redirect', 'https://example.com/redirect'),
        to_url: Html2rss::Url.from_relative('https://example.com/final', 'https://example.com/final'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
    end

    it 'aborts skipped resources without validating navigation policy', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
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
        url: Html2rss::Url.from_relative('https://example.com/image.png', 'https://example.com/image.png'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
    end

    it 'aborts denied non-navigation requests without continuing them', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
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
        url: Html2rss::Url.from_relative('https://127.0.0.1/private', 'https://127.0.0.1/private'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(asset_request).to have_received(:abort)
      expect(asset_request).not_to have_received(:continue)
    end

    it 'raises stored navigation policy errors from goto', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      error = Html2rss::RequestService::PrivateNetworkDenied.new('blocked')
      allow(policy).to receive(:validate_request!).and_raise(error)
      allow(page).to receive(:goto) do
        event_handlers.fetch('request').call(request)
        response
      end

      expect do
        puppet_commander.navigate_to_destination(page, ctx.url)
      end.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, 'blocked')
      expect(request).to have_received(:abort)
    end
  end

  describe '#navigate_to_destination' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'navigates to the given URL' do # rubocop:disable RSpec/ExampleLength
      puppet_commander.navigate_to_destination(page, ctx.url)

      expect(page).to have_received(:goto).with(
        ctx.url,
        wait_until: 'networkidle0',
        referer: 'https://example.com',
        timeout: 30_000
      )
    end
  end

  describe '#body' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'returns the content of the page' do
      result = puppet_commander.body(page)

      expect(result).to eq('<html></html>')
    end
  end
end
