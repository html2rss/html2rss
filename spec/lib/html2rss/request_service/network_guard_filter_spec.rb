# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::NetworkGuardFilter do
  let(:guard) { Html2rss::RequestService::NetworkGuard.new(allow_private_networks: false) }
  let(:url) { Html2rss::Url.from_absolute('https://nat64.test/feed') }

  describe '.extra_options' do
    let(:inactive_event) { /"event_name":"network_guard\.nat64_inactive","httpx_version":"2\.0\.0"/ }

    it 'releases only the NAT64 prefix from the ssrf filter' do
      expect(described_class.extra_options({})).to eq(safe_private_ranges: [Html2rss::RequestService::NetworkGuard::NAT64_PREFIX])
    end

    context 'when the NAT64 release is unsupported' do
      before do
        described_class.instance_variable_set(:@warned_inactive, nil)
        allow(Html2rss::Log).to receive(:warn)
      end

      after { described_class.instance_variable_set(:@warned_inactive, nil) }

      it 'releases nothing and warns once without addresses for an untested HTTPX version', :aggregate_failures do
        stub_const('HTTPX::VERSION', '2.0.0')

        2.times { expect(described_class.extra_options({})).to eq({}) }
        expect(Html2rss::Log).to have_received(:warn).once.with(inactive_event)
      end

      it 'releases nothing when ssrf_filter no longer defines addresses=', :aggregate_failures do
        allow(HTTPX::Plugins::SsrfFilter::ConnectionMethods)
          .to receive(:method_defined?).with(:addresses=).and_return(false)

        expect(described_class.extra_options({})).to eq({})
        expect(Html2rss::Log).to have_received(:warn).once
      end
    end
  end

  describe '.denied?' do
    {
      '2001:4860:4860::8888' => false, '8.8.8.8' => false, '64:ff9b::8.8.8.8' => false,
      '10.0.0.1' => true, '::ffff:10.0.0.1' => true, '64:ff9b::10.0.0.1' => true,
      '64:ff9b::100.64.0.1' => true, '2002:0a00:0001::' => true
    }.each do |ip, expected|
      it "returns #{expected} for #{ip}" do
        expect(described_class.denied?(IPAddr.new(ip))).to be(expected)
      end
    end
  end

  describe 'ConnectionMethods#addresses=' do
    let(:entry) { Struct.new(:address) }
    let(:connection_class) do
      Class.new do
        attr_reader :got

        def addresses=(addrs)
          @got = addrs
        end
      end
    end
    let(:connection) do
      connection_class.prepend(described_class::ConnectionMethods)
      connection_class.new
    end

    it 'drops denied entries and forwards the rest' do
      connection.addresses = %w[64:ff9b::10.0.0.1 64:ff9b::8.8.8.8].map { |ip| entry.new(IPAddr.new(ip)) }

      expect(connection.got.map { |e| e.address.to_s }).to eq(['64:ff9b::808:808'])
    end
  end

  describe 'through a real HTTPX session' do
    before { allow(HTTPX::TCP).to receive(:new).and_call_original }

    # Real HTTPX stack (filter, connection, socket layer) with the HTTP mocks stepped aside.
    # Resolution is stubbed through HTTPX's +addresses+ option: no DNS, no network. The session is
    # built here, not memoized, so the mock-free session never leaks into other examples.
    def fetch(ip)
      WebMock.disable!
      VCR.turned_off do
        HTTPX.plugin(described_class)
             .with(addresses: { 'nat64.test' => [ip] }, timeout: { connect_timeout: 0.2 })
             .get('https://nat64.test/feed')
      end
    ensure
      WebMock.enable!
    end

    it 'sits ahead of ssrf_filter in connection method resolution (HTTPX 1.9.x ordering)' do
      session = Html2rss::RequestService::HttpxStrategy.base_ssrf_session
      ancestors = session.class.default_options.connection_class.ancestors

      expect(ancestors.index(described_class::ConnectionMethods))
        .to be < ancestors.index(HTTPX::Plugins::SsrfFilter::ConnectionMethods)
    end

    %w[64:ff9b::10.0.0.1 64:ff9b::169.254.169.254 64:ff9b::100.64.0.1 64:ff9b:1::808:808
       2002:0a00:0001:: 2001::1].each do |ip|
      it "refuses #{ip} before any socket is opened", :aggregate_failures do
        expect(fetch(ip).error).to be_a(HTTPX::ServerSideRequestForgeryError)
        expect(HTTPX::TCP).not_to have_received(:new)
      end
    end

    %w[64:ff9b::10.0.0.1 64:ff9b::169.254.169.254 64:ff9b:1::808:808 2002:0a00:0001:: 2001::1].each do |ip|
      it "has the guard deny the connected peer #{ip}" do
        expect { guard.validate_remote_ip!(ip:, url:) }
          .to raise_error(Html2rss::RequestService::PrivateNetworkDenied)
      end
    end

    it 'lets a public NAT64 address reach the socket layer', :aggregate_failures do
      expect(fetch('64:ff9b::8.8.8.8').error).not_to be_a(HTTPX::ServerSideRequestForgeryError)
      expect(HTTPX::TCP).to have_received(:new)
    end

    [
      ['an untested HTTPX version', -> { stub_const('HTTPX::VERSION', '2.0.0') }],
      ['a missing addresses= hook', lambda {
        allow(HTTPX::Plugins::SsrfFilter::ConnectionMethods).to receive(:method_defined?).and_call_original
        allow(HTTPX::Plugins::SsrfFilter::ConnectionMethods).to receive(:method_defined?)
          .with(:addresses=).and_return(false)
      }]
    ].each do |label, setup|
      it "still refuses a public NAT64 address with #{label}", :aggregate_failures do
        allow(Html2rss::Log).to receive(:warn)
        instance_exec(&setup)

        expect(fetch('64:ff9b::8.8.8.8').error).to be_a(HTTPX::ServerSideRequestForgeryError)
        expect(HTTPX::TCP).not_to have_received(:new)
      end
    end

    it 'accepts the connected peer of a public NAT64 address' do
      expect { guard.validate_remote_ip!(ip: '64:ff9b::8.8.8.8', url:) }.not_to raise_error
    end
  end
end
