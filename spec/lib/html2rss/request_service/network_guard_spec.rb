# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::NetworkGuard do
  subject(:guard) { described_class.new(allow_private_networks: false, resolver:) }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/feed') }
  let(:resolver) { instance_double(Resolv) }
  let(:denied) { Html2rss::RequestService::PrivateNetworkDenied }
  let(:refuses) do
    lambda do
      guard.enforce_public_network!(url)
      false
    rescue denied
      true
    end
  end

  blocked_ips = %w[
    0.0.0.0 0.255.255.255 10.0.0.1 10.255.255.255 127.0.0.1 127.255.255.255 169.254.169.254 172.16.0.1
    172.31.255.255 192.168.0.1 192.168.255.255 224.0.0.1 239.255.255.255 ::1 :: fe80::1 febf::1 fc00::1
    100.64.0.1 100.127.255.255 192.0.0.1 192.0.2.1 192.88.99.1 198.18.0.1 198.19.255.255 198.51.100.1 203.0.113.1
    240.0.0.1 255.255.255.255 100::1 2001:10::1 2001:20::1 2001:db8::1
    fdff::1 ff02::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1 ::ffff:169.254.169.254
    64:ff9b::10.0.0.1 64:ff9b::127.0.0.1 64:ff9b::169.254.169.254 64:ff9b::192.168.1.1 64:ff9b::0.0.0.0
    64:ff9b::224.0.0.1 64:ff9b:1::1 64:ff9b:1::808:808 2002:0a00:0001:: 2002:7f00:0001:: 2002:a9fe:a9fe::1
    2002:c0a8:0101:: 2001:0:4136:e378:8000:63bf:f5ff:fffe 2001::1
  ]
  public_ips = %w[
    1.1.1.1 8.8.8.8 9.255.255.255 11.0.0.1 126.255.255.255 128.0.0.1 169.253.255.255 169.255.0.1 172.15.255.255
    172.32.0.1 192.167.255.255 192.169.0.1 223.255.255.255 2001:4860:4860::8888 ::ffff:8.8.8.8
    64:ff9b::8.8.8.8 64:ff9b::1.1.1.1 2002:0808:0808:: 2001:1::1
  ]

  # Independent oracle for the :property examples: the special-purpose registries, spelled out apart from the guard.
  expected_ranges = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
    192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 100::/64 2001:10::/28 2001:20::/28 2001:db8::/32 fe80::/10 fc00::/7 ff00::/8
    64:ff9b:1::/48 2001::/32
  ].map { |cidr| IPAddr.new(cidr) }

  describe '#enforce_public_network!' do
    it 'refuses a host iff it resolves to nothing or any address is blocked', :property do
      forall(PropertyGenerators.resolver_answer(expected_ranges)) do |found|
        allow(resolver).to found.inject(receive(:each_address).with('example.com')) { |c, ip| c.and_yield(ip.to_s) }
        expect(refuses.call).to be(found.empty? || found.any? { |address| guard.blocked_ip?(address) })
      end
    end

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
        allow(resolver).to receive(:each_address).with('example.com').and_yield('8.8.8.8')
      end

      it 'classifies addresses via each_address' do
        expect { guard.enforce_public_network!(url) }.not_to raise_error
      end
    end

    context 'when the resolver times out' do
      before { allow(resolver).to receive(:each_address).and_raise(Resolv::ResolvTimeout) }

      it 'fails closed' do
        expect { guard.enforce_public_network!(url) }.to raise_error(denied, /example.com/)
      end
    end

    context 'when a getaddrinfo-only object is not Socket' do
      let(:resolver) do
        Class.new do
          def self.getaddrinfo(*)
            [[nil, nil, nil, '8.8.8.8']]
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

    %w[localhost LOCALHOST localhost. foo.localhost foo.localhost. localhost.localdomain
       metadata.google.internal].each do |host|
      it "denies host #{host} without resolving", :aggregate_failures do
        allow(resolver).to receive(:each_address)

        expect { guard.enforce_public_network!(Html2rss::Url.from_absolute("http://#{host}/")) }
          .to raise_error(denied, /#{host}/i)
        expect(resolver).not_to have_received(:each_address)
      end
    end

    it 'does not treat look-alike hosts as local' do
      allow(resolver).to receive(:each_address).and_yield('8.8.8.8')

      expect { guard.enforce_public_network!(Html2rss::Url.from_absolute('http://notlocalhost.example/')) }
        .not_to raise_error
    end

    it 'does not resolve IP literals', :aggregate_failures do
      allow(resolver).to receive(:each_address)

      expect { guard.enforce_public_network!(Html2rss::Url.from_absolute('http://8.8.8.8/')) }.not_to raise_error
      expect(resolver).not_to have_received(:each_address)
    end

    it 'denies when any resolved address is blocked' do
      allow(resolver).to receive(:each_address).with('example.com').and_yield('8.8.8.8').and_yield('10.0.0.1')

      expect { guard.enforce_public_network!(url) }.to raise_error(denied, /example.com/)
    end

    it 'ignores unparsable resolver addresses but keeps valid ones' do
      allow(resolver).to receive(:each_address).with('example.com').and_yield('garbage').and_yield('8.8.8.8')

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
    it 'denies every address inside a blocked range, in every spelling', :property do
      forall(PropertyGenerators.address_in(expected_ranges)) do |address|
        spellings = [address.to_s, address.to_s.upcase, address.to_string, address.to_string.upcase].uniq
        expect(spellings.map { |text| guard.blocked_ip?(IPAddr.new(text)) }).to all(be(true))
      end
    end

    it 'judges IPv4 by the ranges in plain, IPv4-mapped, NAT64 and 6to4 forms', :property do
      forall(PropertyGenerators.random_ipv4) do |address|
        expected = expected_ranges.any? { |range| range.include?(address) }
        expect(PropertyGenerators.ipv6_forms(address).map { |form| guard.blocked_ip?(form) }).to all(be(expected))
      end
    end

    blocked_ips.each do |ip|
      it("denies #{ip}") { expect(guard.blocked_ip?(IPAddr.new(ip))).to be(true) }
    end

    public_ips.each do |ip|
      it("allows public #{ip}") { expect(guard.blocked_ip?(IPAddr.new(ip))).to be(false) }
    end
  end

  describe 'HTTPX ssrf_filter parity' do
    # Judged on the embedded IPv4 (NAT64, 6to4) or by IPAddr#native (IPv4-mapped), or malformed ranges HTTPX
    # derives in ::/80 that no client can reach. A new HTTPX range is never skipped unless listed here.
    let(:excluded_keys) do
      %w[
        64:ff9b::/96 2002::/16 ::ff00:0:0/88 ::ffc0:0:0/90 ::fff0:0:0/92 ::f000:0:0/84 ::fffe:0:0/95
        ::ffff:0.0.0.0/96 ::ffff:192.0.0.0/104 ::ffff:198.0.0.0/104 ::ffff:203.0.0.0/104 ::ffff:255.255.0.0/112
      ]
    end

    it 'excludes only ranges HTTPX still lists' do
      keys = (HTTPX::Plugins::SsrfFilter::IPV4_BLACKLIST + HTTPX::Plugins::SsrfFilter::IPV6_BLACKLIST)
             .map { |range| "#{range.to_range.first}/#{range.prefix}" }

      expect(keys & excluded_keys).to match_array(excluded_keys)
    end

    (HTTPX::Plugins::SsrfFilter::IPV4_BLACKLIST + HTTPX::Plugins::SsrfFilter::IPV6_BLACKLIST).each do |range|
      it "denies the network address of #{range.to_range.first}/#{range.prefix}" do
        next if excluded_keys.include?("#{range.to_range.first}/#{range.prefix}")

        expect(guard.blocked_ip?(range.to_range.first)).to be(true)
      end
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
