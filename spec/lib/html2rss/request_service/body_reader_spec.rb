# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::BodyReader do
  subject(:reader) { described_class.new(stream, policy:, url: Html2rss::Url.from_absolute('https://example.com')) }

  let(:content_type) { 'text/html' }
  let(:chunks) { [] }
  let(:pulled) { [] }
  # rubocop:disable-next RSpec/VerifiedDoubles -- StreamResponse delegates via method_missing
  let(:stream) do
    headers = instance_double(HTTPX::Headers, to_h: { 'content-type' => content_type })
    double('stream', status: 200, headers:, uri: URI('https://example.com')).tap do |double|
      allow(double).to receive(:each) do |&block|
        chunks.each do |chunk|
          pulled << chunk
          block.call(chunk)
        end
      end
    end
  end
  let(:policy) do
    instance_double(Html2rss::RequestService::Policy, max_stream_bytes: 4000).tap do |double|
      allow(double).to receive(:max_decompressed_bytes_for) { |response| response.feed_response? ? 4000 : 2000 }
    end
  end

  context 'when an HTML body crosses its cap before the stream ends' do
    let(:chunks) { Array.new(20) { 'a' * 500 } }

    it 'raises and stops pulling chunks', :aggregate_failures do
      expect { reader.read }.to raise_error(Html2rss::RequestService::ResponseTooLarge, 'Response exceeded 2000 bytes')
      expect(pulled.size).to eq(5)
    end
  end

  context 'when a feed body sits between the HTML cap and the feed cap' do
    let(:content_type) { 'application/rss+xml' }
    let(:chunks) { Array.new(6) { 'a' * 500 } }

    it 'reads the whole body', :aggregate_failures do
      streamed = reader.read

      expect(streamed.body.bytesize).to eq(3000)
      expect([streamed.status, streamed.uri.to_s]).to eq([200, 'https://example.com'])
      expect(streamed.headers).to be(stream.headers)
    end
  end

  context 'when an HTML page mentioning a feed tag arrives as octet-stream' do
    let(:content_type) { 'application/octet-stream' }
    let(:chunks) { ['<!DOCTYPE html><html><body><rss>', 'a' * 1500, 'b' * 1500] }

    it 'applies the HTML cap to the sniffed head' do
      expect { reader.read }.to raise_error(Html2rss::RequestService::ResponseTooLarge, /2000 bytes/)
    end
  end

  context 'when an HTML body is one byte over its cap' do
    let(:chunks) { ['a' * 1000, 'b' * 1001] }

    it 'raises' do
      expect { reader.read }.to raise_error(Html2rss::RequestService::ResponseTooLarge)
    end
  end

  context 'when an HTML body is exactly at its cap' do
    let(:chunks) { ['a' * 1000, 'b' * 1000] }

    it 'passes' do
      expect(reader.read.body.bytesize).to eq(2000)
    end
  end

  context 'when the body is shorter than the sniff window' do
    let(:chunks) { ['a' * 500, 'b' * 500] }

    it 'keeps the widest cap and never asks for the per-type one' do
      reader.read

      expect(policy).not_to have_received(:max_decompressed_bytes_for)
    end
  end

  context 'when the type is only visible in the body' do
    let(:content_type) { 'application/octet-stream' }
    let(:chunks) { ["<?xml version=\"1.0\"?><rss version=\"2.0\">#{'a' * 1500}", 'b' * 1500, 'c' * 900] }

    it 'applies the feed cap once, classifying the head against the request URL', :aggregate_failures do
      expect(reader.read.body.bytesize).to be > 3900
      expect(policy).to have_received(:max_decompressed_bytes_for)
        .with(an_object_having_attributes(url: Html2rss::Url.from_absolute('https://example.com'))).once
    end
  end

  context 'when the transport raises a 4xx status error after the chunks' do
    # rubocop:disable-next RSpec/VerifiedDoubles -- StreamResponse delegates via method_missing
    let(:stream) do
      headers = instance_double(HTTPX::Headers, to_h: {})
      double('stream', status: 404, headers:, uri: URI('https://example.com')).tap do |double|
        allow(double).to receive(:each) do |&block|
          block.call('gone')
          raise HTTPX::HTTPError, instance_double(HTTPX::Response, status: 404, headers: {}, body: '')
        end
      end
    end

    it 'returns the body and status', :aggregate_failures do
      streamed = reader.read

      expect([streamed.body, streamed.status]).to eq(['gone', 404])
    end
  end
end
