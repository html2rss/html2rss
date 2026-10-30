# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Policy do
  subject(:policy) { described_class.new(resolver:, **options) }

  let(:options) { {} }
  let(:resolver) { instance_double(Resolv) }
  let(:origin_url) { Html2rss::Url.from_absolute('https://example.com/feed') }

  describe '#initialize' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    let(:options) { { max_requests: described_class::MAX_REQUESTS_CEILING + 5 } }

    it 'clamps request budgets to the policy ceiling' do
      expect(policy.max_requests).to eq(described_class::MAX_REQUESTS_CEILING)
    end
  end

  describe '#validate_request!' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
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

    context 'when DNS resolution returns no addresses' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com')
      end

      it 'rejects the request' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
      end
    end

    context 'when DNS resolution encounters a socket error' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }

      before do
        allow(resolver).to receive(:each_address).with('example.com')
                                                 .and_raise(SocketError, 'getaddrinfo: nodename nor servname provided')
      end

      it 'rejects the request' do
        expect { validate_request! }.to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
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

  describe '#validate_request!' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    subject(:validate_follow_up!) { policy.validate_request!(url:, origin_url:, relation: :pagination) }

    let(:origin_url) { Html2rss::Url.from_absolute('https://example.com/feed') }

    before do
      allow(resolver).to receive(:each_address).and_yield('93.184.216.34')
    end

    context 'when the follow-up shares host and default port with the origin' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com:443/feed?page=2') }

      it 'allows the follow-up' do
        expect { validate_follow_up! }.not_to raise_error
      end
    end

    context 'when the follow-up shares host but uses a different port' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com:8443/feed?page=2') }

      it 'rejects the follow-up as cross-origin' do
        expect { validate_follow_up! }.to raise_error(Html2rss::RequestService::CrossOriginFollowUpDenied)
      end
    end

    context 'when the follow-up points at another host on the same port' do
      let(:url) { Html2rss::Url.from_absolute('https://example.org/feed?page=2') }

      it 'rejects the follow-up as cross-origin' do
        expect { validate_follow_up! }.to raise_error(Html2rss::RequestService::CrossOriginFollowUpDenied)
      end
    end

    context 'when both origin and follow-up are plain http' do
      let(:origin_url) { Html2rss::Url.from_absolute('http://example.com/feed') }
      let(:url) { Html2rss::Url.from_absolute('http://example.com/feed?page=2') }

      it 'allows the follow-up without a scheme error' do
        expect { validate_follow_up! }.not_to raise_error
      end
    end

    context 'when an https origin follows up over plain http' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com/feed?page=2') }

      it 'names the downgraded follow-up url', :aggregate_failures do
        expect { validate_follow_up! }.to raise_error(
          Html2rss::RequestService::UnsupportedUrlScheme,
          'Follow-up downgraded from https to http for http://example.com/feed?page=2'
        )
      end
    end
  end

  describe '#initialize' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    let(:minimal_limits) do
      {
        connect_timeout_seconds: 1, read_timeout_seconds: 1, total_timeout_seconds: 1, max_redirects: 0,
        max_response_bytes: 1, max_decompressed_bytes: 1, max_requests: 1
      }
    end

    it 'exposes the configured limits as readers', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      limits = described_class.new(
        resolver:, connect_timeout_seconds: 2, read_timeout_seconds: 3, total_timeout_seconds: 4,
        max_redirects: 0, max_response_bytes: 100, max_decompressed_bytes: 200, max_requests: 2
      )

      expect(limits).to have_attributes(
        connect_timeout_seconds: 2, read_timeout_seconds: 3, total_timeout_seconds: 4,
        max_redirects: 0, max_response_bytes: 100, max_decompressed_bytes: 200, max_requests: 2
      )
    end

    it 'uses the documented defaults when no limits are given', :aggregate_failures do
      expect(policy).to have_attributes(
        max_redirects: 5, max_response_bytes: 5_242_880, max_decompressed_bytes: 10_485_760, max_requests: 1
      )
      expect(policy.allow_private_networks?).to be(false)
      expect(policy.allow_cross_origin_followups?).to be(false)
    end

    it 'treats truthy flag values as enabled', :aggregate_failures do
      flagged = described_class.new(resolver:, allow_private_networks: 'yes', allow_cross_origin_followups: 1)

      expect(flagged.allow_private_networks?).to be(true)
      expect(flagged.allow_cross_origin_followups?).to be(true)
    end

    it 'builds the shared default policy with one request' do
      expect(described_class.default).to have_attributes(max_requests: 1, allow_private_networks?: false)
    end

    it 'accepts the lowest valid limits and rejects values below them', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(described_class.new(resolver:, **minimal_limits)).to have_attributes(minimal_limits)
      expect { described_class.new(resolver:, connect_timeout_seconds: 0) }
        .to raise_error(Html2rss::Error, /connect_timeout_seconds/)
      expect { described_class.new(resolver:, read_timeout_seconds: 0) }
        .to raise_error(Html2rss::Error, /read_timeout_seconds/)
      expect { described_class.new(resolver:, total_timeout_seconds: 0) }
        .to raise_error(Html2rss::Error, /total_timeout_seconds/)
      expect { described_class.new(resolver:, max_redirects: -1) }.to raise_error(Html2rss::Error, /max_redirects/)
      expect { described_class.new(resolver:, max_response_bytes: 0) }
        .to raise_error(Html2rss::Error, /max_response_bytes/)
      expect { described_class.new(resolver:, max_decompressed_bytes: 0) }
        .to raise_error(Html2rss::Error, /max_decompressed_bytes/)
      expect { described_class.new(resolver:, max_requests: 0) }.to raise_error(Html2rss::Error, /max_requests/)
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

      it 'rejects the redirect and names the hop', :aggregate_failures do
        expect { validate_redirect! }.to raise_error(
          Html2rss::RequestService::UnsupportedUrlScheme,
          'Redirect downgraded from https://example.com/feed to http://example.com/feed'
        )
      end
    end

    context 'when the redirect stays acceptable' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:to_url) { Html2rss::Url.from_absolute('https://example.com/other') }

      it 'allows the redirect' do
        expect { validate_redirect! }.not_to raise_error
      end
    end

    context 'when a plain http redirect stays on http' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:from_url) { Html2rss::Url.from_absolute('http://example.com/feed') }
      let(:to_url) { Html2rss::Url.from_absolute('http://example.com/other') }

      it 'allows the redirect because no https downgrade happens' do
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

    context 'when the response IP is nil' do
      let(:ip) { nil }

      it 'rejects the response' do
        expect { validate_remote_ip! }.to raise_error(
          Html2rss::RequestService::PrivateNetworkDenied,
          /Remote IP could not be validated/
        )
      end
    end

    context 'when the response IP is empty' do
      let(:ip) { '' }

      it 'rejects the response' do
        expect { validate_remote_ip! }.to raise_error(
          Html2rss::RequestService::PrivateNetworkDenied,
          /Remote IP could not be validated/
        )
      end
    end

    context 'when private networks are allowed' do
      let(:options) { { allow_private_networks: true } }
      let(:ip) { '127.0.0.1' }

      it 'allows private response IPs' do
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
