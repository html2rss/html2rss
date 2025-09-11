# frozen_string_literal: true

require 'spec_helper'
require 'puppeteer'

RSpec.describe Html2rss::RequestService::PuppetCommander do
  let(:ctx) do
    instance_double(Html2rss::RequestService::Context,
                    url: Html2rss::Url.from_relative('https://example.com', 'https://example.com'),
                    headers: { 'User-Agent' => 'RSpec' })
  end
  let(:browser) { instance_double(Puppeteer::Browser, new_page: page) }
  let(:page) { instance_double(Puppeteer::Page) }
  let(:response) { instance_double(Puppeteer::HTTPResponse, headers: { 'Content-Type' => 'text/html' }) }
  let(:puppet_commander) { described_class.new(ctx, browser) }

  before do
    allow(page).to receive(:extra_http_headers=)
    allow(page).to receive(:request_interception=)
    allow(page).to receive(:on)
    allow(page).to receive_messages(goto: response, content: '<html></html>')
    allow(page).to receive(:close)
  end

  describe '#call' do
    it 'returns a Response with the correct body and headers', :aggregate_failures do
      result = puppet_commander.call

      expect(result.body).to eq('<html></html>')
      expect(result.headers).to eq({ 'Content-Type' => 'text/html' })
    end

    it 'closes the page after execution' do
      puppet_commander.call

      expect(page).to have_received(:close)
    end
  end

  describe '#new_page' do
    it 'sets extra HTTP headers on the page' do
      puppet_commander.new_page

      expect(page).to have_received(:extra_http_headers=).with(ctx.headers)
    end

    it 'sets up request interception if skip_request_resources is not empty', :aggregate_failures do
      puppet_commander.new_page

      expect(page).to have_received(:request_interception=).with(true)
      expect(page).to have_received(:on).with('request')
    end
  end

  describe '#navigate_to_destination' do
    it 'navigates to the given URL' do
      puppet_commander.navigate_to_destination(page, ctx.url)

      expect(page).to have_received(:goto).with(ctx.url, wait_until: 'networkidle0', referer: 'https://example.com')
    end
  end

  describe '#body' do
    it 'returns the content of the page' do
      result = puppet_commander.body(page)

      expect(result).to eq('<html></html>')
    end
  end
end
