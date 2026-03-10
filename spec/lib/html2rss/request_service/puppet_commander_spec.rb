# frozen_string_literal: true

require 'spec_helper'
require 'puppeteer'

RSpec.describe Html2rss::RequestService::PuppetCommander do # rubocop:disable RSpec/MultipleMemoizedHelpers
  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      total_timeout_seconds: 30,
      max_decompressed_bytes: 5_242_880,
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
  let(:response) do
    instance_double(
      Puppeteer::HTTPResponse,
      headers: { 'Content-Type' => 'text/html' },
      url: 'https://example.com/articles',
      remote_address: instance_double(Puppeteer::HTTPResponse::RemoteAddress, ip: '93.184.216.34')
    )
  end
  let(:puppet_commander) { described_class.new(ctx, browser) }

  before do
    allow(page).to receive(:extra_http_headers=)
    allow(page).to receive(:default_navigation_timeout=)
    allow(page).to receive(:default_timeout=)
    allow(page).to receive(:request_interception=)
    allow(page).to receive(:on)
    allow(page).to receive_messages(goto: response, content: '<html></html>')
    allow(page).to receive(:close)
  end

  describe '#call' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'returns a Response with the correct body and headers', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      result = puppet_commander.call

      expect(result.body).to eq('<html></html>')
      expect(result.headers).to eq({ 'Content-Type' => 'text/html' })
      expect(policy).to have_received(:validate_redirect!).with(
        from_url: ctx.url,
        to_url: Html2rss::Url.from_relative('https://example.com/articles', 'https://example.com/articles'),
        origin_url: ctx.origin_url,
        relation: :initial
      )
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

    it 'sets page timeouts from the request policy', :aggregate_failures do
      puppet_commander.new_page

      expect(page).to have_received(:default_navigation_timeout=).with(30_000)
      expect(page).to have_received(:default_timeout=).with(30_000)
    end

    it 'sets up request interception if skip_request_resources is not empty', :aggregate_failures do
      puppet_commander.new_page

      expect(page).to have_received(:request_interception=).with(true)
      expect(page).to have_received(:on).with('request')
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
