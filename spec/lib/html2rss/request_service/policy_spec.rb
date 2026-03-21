# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Policy do
  subject(:policy) { described_class.new(resolver:, **options) }

  let(:options) { {} }
  let(:resolver) { instance_double(Resolv) }
  let(:origin_url) { Html2rss::Url.from_absolute('https://example.com/feed') }

  describe '#initialize' do
    let(:options) { { max_requests: described_class::MAX_REQUESTS_CEILING + 5 } }

    it 'clamps request budgets to the policy ceiling' do
      expect(policy.max_requests).to eq(described_class::MAX_REQUESTS_CEILING)
    end
  end

  describe '#validate_request!' do
    subject(:validate_request!) { policy.validate_request!(url:, origin_url:, relation:) }

    let(:relation) { :initial }

    context 'when the host resolves to a private IP' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('127.0.0.1')
      end

      it 'raises a private-network error' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
      end
    end

    context 'when a follow-up leaves the origin host' do
      let(:relation) { :pagination }
      let(:url) { Html2rss::Url.from_absolute('https://other.example.com/page/2') }

      before do
        allow(resolver).to receive(:each_address)
      end

      it 'rejects the follow-up' do
        expect { validate_request! }.to raise_error(
          Html2rss::RequestService::CrossOriginFollowUpDenied,
          /other\.example\.com/
        )
      end
    end

    context 'when a follow-up downgrades from https to http on the same host' do
      let(:relation) { :auto_source }
      let(:url) { Html2rss::Url.from_absolute('http://example.com/wp-json/wp/v2/posts') }

      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('93.184.216.34')
      end

      it 'rejects the downgrade' do
        expect { validate_request! }.to raise_error(
          Html2rss::RequestService::UnsupportedUrlScheme,
          /Follow-up downgraded from https to http/
        )
      end
    end

    context 'when the host is blocked before DNS resolution' do
      let(:url) { Html2rss::Url.from_absolute('https://localhost/feed') }

      it 'rejects localhost' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /localhost/)
      end
    end

    context 'when the host is a known metadata hostname' do
      let(:url) do
        Html2rss::Url.from_relative(
          'https://metadata.google.internal/computeMetadata/v1/',
          'https://metadata.google.internal/computeMetadata/v1/'
        )
      end

      it 'rejects the request' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied,
                                                    /metadata\.google\.internal/)
      end
    end

    context 'when the host resolves to a public IP' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('93.184.216.34')
      end

      it 'allows the request' do
        expect { validate_request! }.not_to raise_error
      end
    end

    context 'when DNS yields an address string that IPAddr cannot classify cleanly' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com')
                                                 .and_yield('weird-address')
                                                 .and_yield('93.184.216.34')
        allow(IPAddr).to receive(:new).and_call_original
        allow(IPAddr).to receive(:new).with('weird-address').and_raise(
          IPAddr::AddressFamilyError, 'address family must be specified'
        )
      end

      it 'ignores the malformed address and allows the request' do
        expect { validate_request! }.not_to raise_error
      end
    end

    context 'when the host resolves to an IPv6 loopback address' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('::1')
      end

      it 'rejects the request' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
      end
    end

    context 'when the host resolves to an IPv6 unique local address' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('fd12:3456:789a::1')
      end

      it 'rejects the request' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
      end
    end

    context 'when private networks are allowed' do
      let(:options) { { allow_private_networks: true } }
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('127.0.0.1')
      end

      it 'allows the request' do
        expect { validate_request! }.not_to raise_error
      end
    end

    context 'when cross-origin follow-ups are allowed' do
      let(:options) { { allow_cross_origin_followups: true } }
      let(:relation) { :pagination }
      let(:url) do
        Html2rss::Url.from_absolute('https://other.example.com/page/2')
      end

      before do
        allow(resolver).to receive(:each_address).with('other.example.com').and_yield('93.184.216.34')
      end

      it 'allows the follow-up' do
        expect { validate_request! }.not_to raise_error
      end
    end
  end

  describe '#validate_redirect!' do
    subject(:validate_redirect!) { policy.validate_redirect!(from_url:, to_url:, origin_url:, relation:) }

    let(:from_url) { Html2rss::Url.from_absolute('https://example.com/feed') }
    let(:relation) { :initial }

    before do
      allow(resolver).to receive(:each_address).with('example.com').and_yield('93.184.216.34')
    end

    context 'when the redirect downgrades the scheme' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:to_url) { Html2rss::Url.from_absolute('http://example.com/feed') }

      it 'rejects the redirect' do
        expect { validate_redirect! }.to raise_error(Html2rss::RequestService::UnsupportedUrlScheme,
                                                     'Redirect downgraded from https to http')
      end
    end

    context 'when the redirect stays acceptable' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:to_url) { Html2rss::Url.from_absolute('https://example.com/other') }

      it 'allows the redirect' do
        expect { validate_redirect! }.not_to raise_error
      end
    end

    context 'when the redirect crosses origin on a follow-up request' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:relation) { :pagination }
      let(:to_url) do
        Html2rss::Url.from_absolute('https://other.example.com/other')
      end

      it 'rejects the redirect' do
        expect { validate_redirect! }.to raise_error(Html2rss::RequestService::CrossOriginFollowUpDenied,
                                                     /other\.example\.com/)
      end
    end
  end

  describe '#validate_remote_ip!' do
    subject(:validate_remote_ip!) { policy.validate_remote_ip!(ip:, url:) }

    let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

    context 'when the response IP is private' do
      let(:ip) { '127.0.0.1' }

      it 'rejects the response' do
        expect { validate_remote_ip! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
      end
    end

    context 'when the response IP is public' do
      let(:ip) { '93.184.216.34' }

      it 'allows the response' do
        expect { validate_remote_ip! }.not_to raise_error
      end
    end

    context 'when the response IP cannot be classified by IPAddr' do
      let(:ip) { 'weird-address' }

      before do
        allow(IPAddr).to receive(:new).and_call_original
        allow(IPAddr).to receive(:new).with('weird-address').and_raise(
          IPAddr::AddressFamilyError, 'address family must be specified'
        )
      end

      it 'rejects the response because the remote IP cannot be validated' do
        expect { validate_remote_ip! }.to raise_error(
          Html2rss::RequestService::PrivateNetworkDenied,
          /Remote IP could not be validated/
        )
      end
    end
  end
end
