# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::NetworkGuard do
  subject(:guard) { described_class.new(allow_private_networks: false, resolver:) }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }
  let(:resolver) { instance_double(Resolv) }

  describe '#enforce_public_network!' do
    context 'when the resolver is Socket' do
      let(:resolver) { Socket }

      before do
        allow(Socket).to receive(:getaddrinfo).with('example.com', nil)
                                              .and_return([[nil, nil, nil, '127.0.0.1']])
      end

      it 'classifies addresses via getaddrinfo' do
        expect { guard.enforce_public_network!(url) }
          .to raise_error(Html2rss::RequestService::PrivateNetworkDenied, /example.com/)
      end
    end

    context 'when the resolver is Resolv-shaped' do
      before do
        allow(resolver).to receive(:each_address).with('example.com').and_yield('93.184.216.34')
      end

      it 'classifies addresses via each_address' do
        expect { guard.enforce_public_network!(url) }.not_to raise_error
      end
    end

    context 'when a getaddrinfo-only object is not Socket' do
      let(:resolver) do
        Class.new do
          def self.getaddrinfo(*)
            [[nil, nil, nil, '93.184.216.34']]
          end
        end
      end

      it 'requires each_address instead of treating it as Socket' do
        expect { guard.enforce_public_network!(url) }.to raise_error(NoMethodError, /each_address/)
      end
    end
  end
end
