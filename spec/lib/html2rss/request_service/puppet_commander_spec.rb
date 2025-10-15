# frozen_string_literal: true

require 'spec_helper'
require 'puppeteer'

RSpec.describe Html2rss::RequestService::PuppetCommander do
  subject(:commander) { described_class.new(ctx, browser) }

  let(:ctx) do
    instance_double(
      Html2rss::RequestService::Context,
      url: Html2rss::Url.from_relative('https://example.com', 'https://example.com'),
      headers: { 'User-Agent' => 'RSpec' },
      browserless_preload: nil
    )
  end
  let(:browser) { instance_double(Puppeteer::Browser, new_page: page) }
  let(:page) { instance_double(Puppeteer::Page) }

  before do
    allow(page).to receive(:extra_http_headers=)
    allow(page).to receive(:request_interception=)
    allow(page).to receive(:on)
  end

  describe '#call' do
    let(:html_body) { +'<html></html>' }

    before do
      response = instance_double(Puppeteer::HTTPResponse, headers: { 'Content-Type' => 'text/html' })

      allow(page).to receive(:content) { html_body }
      allow(page).to receive(:wait_for_timeout)
      allow(page).to receive_messages(
        goto: response,
        query_selector: nil,
        evaluate: nil,
        close: nil
      )
    end

    it 'returns a Response with the correct body and headers', :aggregate_failures do
      result = commander.call

      expect(result.body).to eq('<html></html>')
      expect(result.headers).to eq({ 'Content-Type' => 'text/html' })
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

    it 'sets up request interception if skip_request_resources is not empty', :aggregate_failures do
      commander.new_page

      expect(page).to have_received(:request_interception=).with(true)
      expect(page).to have_received(:on).with('request')
    end
  end

  describe '#navigate_to_destination' do
    let(:response) { instance_double(Puppeteer::HTTPResponse, headers: { 'Content-Type' => 'text/html' }) }

    before { allow(page).to receive(:goto).and_return(response) }

    it 'navigates to the given URL' do
      commander.navigate_to_destination(page, ctx.url)

      expect(page).to have_received(:goto).with(ctx.url, wait_until: 'networkidle0', referer: 'https://example.com')
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
