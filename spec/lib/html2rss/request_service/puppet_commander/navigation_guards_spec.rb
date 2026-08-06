# frozen_string_literal: true

require 'spec_helper'
require 'puppeteer'

RSpec.describe Html2rss::RequestService::PuppetCommander::NavigationGuards do
  subject(:guards) do
    described_class.new(ctx:, skip_request_resources: %w[stylesheet image media font].to_set)
  end

  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
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
      policy:
    )
  end
  let(:page) { instance_double(Puppeteer::Page) }
  let(:request) { mock_request(url: 'https://example.com/articles') }

  def main_frame
    @main_frame ||= instance_double(Puppeteer::Frame)
  end

  def event_handlers
    @event_handlers ||= {}
  end

  def url(str)
    Html2rss::Url.from_absolute(str)
  end

  def redirect_args
    {
      from_url: url('https://example.com/redirect'),
      to_url: url('https://example.com/final'),
      origin_url: ctx.origin_url,
      relation: :initial
    }
  end

  def mock_request(url:, redirect_chain: [], resource_type: 'document', navigation_request: true)
    instance_double(
      Puppeteer::HTTPRequest,
      navigation_request?: navigation_request, url:, redirect_chain:, resource_type:, frame: main_frame
    ).tap do |double|
      allow(double).to receive_messages(continue: nil, abort: nil)
    end
  end

  before do
    allow(page).to receive(:request_interception=)
    allow(page).to receive(:main_frame).and_return(main_frame)
    allow(page).to receive(:on) do |event, &block|
      event_handlers[event] = block
    end
    guards.install!(page)
  end

  describe '.response_url' do
    it 'owns response URL resolution for PuppetCommander and IP validation' do
      response = instance_double(Puppeteer::HTTPResponse, url: 'https://example.com/final')

      expect(described_class.response_url(response, 'https://example.com'))
        .to eq(Html2rss::Url.from_absolute('https://example.com/final'))
    end
  end

  describe 'request interception' do
    it 'validates each navigation request before continuing', :aggregate_failures do
      event_handlers.fetch('request').call(request)
      expect(policy).to have_received(:validate_request!)
        .with(url: url('https://example.com/articles'), origin_url: ctx.origin_url, relation: :initial)
      expect(request).to have_received(:continue)
    end

    it 'validates redirect hops from the request chain' do
      req = mock_request(url: 'https://example.com/final', redirect_chain: [mock_request(url: 'https://example.com/redirect')])

      event_handlers.fetch('request').call(req)
      expect(policy).to have_received(:validate_redirect!).with(**redirect_args)
    end

    it 'aborts skipped resources without continuing them', :aggregate_failures do
      req = mock_request(url: 'https://example.com/image.png', navigation_request: false, resource_type: 'image')

      event_handlers.fetch('request').call(req)
      expect(req).to have_received(:abort)
      expect(policy).to have_received(:validate_request!)
        .with(url: url('https://example.com/image.png'), origin_url: ctx.origin_url, relation: :initial)
    end

    it 'aborts denied non-navigation requests without continuing them', :aggregate_failures do
      req = mock_request(url: 'https://127.0.0.1/private', navigation_request: false, resource_type: 'fetch')
      allow(policy).to receive(:validate_request!).and_raise(Html2rss::RequestService::PrivateNetworkDenied.new('blocked'))

      event_handlers.fetch('request').call(req)
      expect(req).to have_received(:abort)
      expect(req).not_to have_received(:continue)
    end
  end
end
