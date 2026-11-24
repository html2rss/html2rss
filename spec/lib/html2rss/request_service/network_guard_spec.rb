# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::NetworkGuard do
  subject(:guard) { described_class.new(allow_private_networks: false, resolver:) }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }
  let(:resolver) { instance_double(Resolv) }
  let(:denied) { Html2rss::RequestService::PrivateNetworkDenied }

  blocked_ips = %w[
    0.0.0.0 0.255.255.255 10.0.0.1 10.255.255.255 127.0.0.1 127.255.255.255 169.254.169.254 172.16.0.1
    172.31.255.255 192.168.0.1 192.168.255.255 224.0.0.1 239.255.255.255 ::1 :: fe80::1 febf::1 fc00::1
    fdff::1 ff02::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1 ::ffff:169.254.169.254
    64:ff9b::10.0.0.1 64:ff9b::127.0.0.1 64:ff9b::169.254.169.254 64:ff9b::192.168.1.1 64:ff9b::0.0.0.0
    64:ff9b::224.0.0.1 64:ff9b:1::1 64:ff9b:1::808:808 2002:0a00:0001:: 2002:7f00:0001:: 2002:a9fe:a9fe::1
    2002:c0a8:0101:: 2001:0:4136:e378:8000:63bf:f5ff:fffe 2001::1
  ]
  public_ips = %w[
    1.1.1.1 8.8.8.8 9.255.255.255 11.0.0.1 126.255.255.255 128.0.0.1 169.253.255.255 169.255.0.1 172.15.255.255
    172.32.0.1 192.167.255.255 192.169.0.1 223.255.255.255 240.0.0.1 2001:4860:4860::8888 ::ffff:8.8.8.8
    64:ff9b::8.8.8.8 64:ff9b::1.1.1.1 2002:0808:0808:: 2001:1::1
  ]

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
        allow(resolver).to receive(:each_address).with('example.com').and_yield('192.0.2.10')
      end

      it 'classifies addresses via each_address' do
        expect { guard.enforce_public_network!(url) }.not_to raise_error
      end
    end

    context 'when a getaddrinfo-only object is not Socket' do
      let(:resolver) do
        Class.new do
          def self.getaddrinfo(*)
            [[nil, nil, nil, '192.0.2.10']]
          end
        end
      end

      it 'requires each_address instead of treating it as Socket' do
        expect { guard.enforce_public_network!(url) }.to raise_error(NoMethodError, /each_address/)
      end
    end

    blocked_ips.each do |ip|
      it "denies literal #{ip}" do
        target = Html2rss::Url.from_absolute("http://#{ip.include?(':') ? "[#{ip}]" : ip}/")

        expect { guard.enforce_public_network!(target) }.to raise_error(denied, /#{Regexp.escape(target.to_s)}/)
      end
    end

    public_ips.each do |ip|
      it "allows public literal #{ip}" do
        target = Html2rss::Url.from_absolute("http://#{ip.include?(':') ? "[#{ip}]" : ip}/")

        expect { guard.enforce_public_network!(target) }.not_to raise_error
      end
    end

    %w[localhost LOCALHOST localhost.localdomain metadata.google.internal].each do |host|
      it "denies host #{host} without resolving", :aggregate_failures do
        allow(resolver).to receive(:each_address)

        expect { guard.enforce_public_network!(Html2rss::Url.from_absolute("http://#{host}/")) }
          .to raise_error(denied, /#{host}/i)
        expect(resolver).not_to have_received(:each_address)
      end
    end

    it 'does not treat look-alike hosts as local' do
      allow(resolver).to receive(:each_address).and_yield('192.0.2.10')

      expect { guard.enforce_public_network!(Html2rss::Url.from_absolute('http://notlocalhost.example/')) }
        .not_to raise_error
    end

    it 'does not resolve IP literals', :aggregate_failures do
      allow(resolver).to receive(:each_address)

      expect { guard.enforce_public_network!(Html2rss::Url.from_absolute('http://8.8.8.8/')) }.not_to raise_error
      expect(resolver).not_to have_received(:each_address)
    end

    it 'denies when any resolved address is blocked' do
      allow(resolver).to receive(:each_address).with('example.com').and_yield('192.0.2.10').and_yield('10.0.0.1')

      expect { guard.enforce_public_network!(url) }.to raise_error(denied, /example.com/)
    end

    it 'ignores unparsable resolver addresses but keeps valid ones' do
      allow(resolver).to receive(:each_address).with('example.com').and_yield('garbage').and_yield('192.0.2.10')

      expect { guard.enforce_public_network!(url) }.not_to raise_error
    end

    it 'denies when only unparsable addresses resolve' do
      allow(resolver).to receive(:each_address).with('example.com').and_yield('garbage')

      expect { guard.enforce_public_network!(url) }.to raise_error(denied, /example.com/)
    end

    [Resolv::ResolvError, SocketError, Errno::ECONNREFUSED].each do |error|
      it "denies when resolution raises #{error}" do
        allow(resolver).to receive(:each_address).and_raise(error)

        expect { guard.enforce_public_network!(url) }.to raise_error(denied, /example.com/)
      end
    end

    it 'denies when getaddrinfo yields nothing' do
      allow(Socket).to receive(:getaddrinfo).and_return([])
      socket_guard = described_class.new(allow_private_networks: false)

      expect { socket_guard.enforce_public_network!(url) }.to raise_error(denied, /example.com/)
    end

    it 'skips unparsable getaddrinfo entries' do
      allow(Socket).to receive(:getaddrinfo).and_return([[nil, nil, nil, 'garbage'], [nil, nil, nil, '8.8.8.8']])
      socket_guard = described_class.new(allow_private_networks: false)

      expect { socket_guard.enforce_public_network!(url) }.not_to raise_error
    end

    it 'allows private targets when private networks are allowed' do
      open_guard = described_class.new(allow_private_networks: true, resolver:)

      expect { open_guard.enforce_public_network!(Html2rss::Url.from_absolute('http://localhost/')) }
        .not_to raise_error
    end
  end

  describe '#blocked_ip?' do
    blocked_ips.each do |ip|
      it("denies #{ip}") { expect(guard.blocked_ip?(IPAddr.new(ip))).to be(true) }
    end

    public_ips.each do |ip|
      it("allows public #{ip}") { expect(guard.blocked_ip?(IPAddr.new(ip))).to be(false) }
    end
  end

  describe '#embedded_ipv4' do
    {
      '64:ff9b::8.8.8.8' => '8.8.8.8',
      '64:ff9b::10.0.0.1' => '10.0.0.1',
      '64:ff9b::ffff:ffff' => '255.255.255.255',
      '2002:0808:0808::1' => '8.8.8.8',
      '2002:ffff:ffff::' => '255.255.255.255'
    }.each do |ipv6, ipv4|
      it "extracts #{ipv4} from #{ipv6}" do
        expect(guard.embedded_ipv4(IPAddr.new(ipv6))).to eq(IPAddr.new(ipv4))
      end
    end

    %w[2001:4860:4860::8888 64:ff9b:1::808:808 ::ffff:8.8.8.8 8.8.8.8 2003::1].each do |ip|
      it "returns nil for #{ip}" do
        expect(guard.embedded_ipv4(IPAddr.new(ip))).to be_nil
      end
    end
  end
end
