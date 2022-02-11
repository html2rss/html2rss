# frozen_string_literal: true

RSpec.describe Html2rss::Utils do
  describe '.build_absolute_url_from_relative(url, channel_url)' do
    let(:channel_url) { 'https://example.com' }

    {
      '/sprite.svg#play' => 'https://example.com/sprite.svg#play',
      '/search?q=term' => 'https://example.com/search?q=term'
    }.each_pair do |url, uri|
      it { expect(described_class.build_absolute_url_from_relative(url, channel_url).to_s).to eq uri }
    end
  end

  describe '.object_to_xml' do
    context 'with JSON object' do
      let(:hash) { { 'data' => [{ 'title' => 'Headline', 'url' => 'https://example.com' }] } }
      let(:xml) do
        '<object><data><array><object><title>Headline</title><url>https://example.com</url></object></array></data></object>'
      end

      it 'converts the hash to xml' do
        expect(described_class.object_to_xml(hash)).to eq xml
      end
    end

    context 'with JSON array' do
      let(:hash) { [{ 'title' => 'Headline', 'url' => 'https://example.com' }] }
      let(:xml) do
        '<array><object><title>Headline</title><url>https://example.com</url></object></array>'
      end

      it 'converts the hash to xml' do
        expect(described_class.object_to_xml(hash)).to eq xml
      end
    end
  end

  describe '.sanitize_url(url)' do
    let(:examples) do
      {
        nil => nil,
        ' ' => nil,
        ' http://example.com/ ' => 'http://example.com/',
        'http://ex.ampl/page?sc=345s#abc' => 'http://ex.ampl/page?sc=345s#abc',
        'https://example.com/sprite.svg#play' =>
          'https://example.com/sprite.svg#play',
        'mailto:bogus@void.space' => 'mailto:bogus@void.space',
        'http://übermedien.de' => 'http://xn--bermedien-p9a.de/',
        'http://www.詹姆斯.com/' => 'http://www.xn--8ws00zhy3a.com/'
      }
    end

    it 'sanitizes the url', aggregate_failures: true do
      examples.each_pair do |url, out|
        expect(described_class.sanitize_url(url)).to eq(out), url
      end
    end
  end

  describe '.use_zone(time_zone)' do
    context 'without given block' do
      it do
        expect { described_class.use_zone('Europe/Berlin') }.to raise_error ArgumentError, /block is required/
      end
    end
  end

  describe '.titleized_url' do
    {
      'http://www.example.com' => 'www.example.com',
      'http://www.example.com/foobar' => 'www.example.com: Foobar',
      'http://www.example.com/foobar/baz' => 'www.example.com: Foobar Baz'
    }.each_pair do |url, expected|
      it { expect(described_class.titleized_url(url)).to eq(expected) }
    end
  end

  describe '.request_body_from_url(url, convert_json_to_xml: false, headers: {})' do
    let(:url) { 'http://example.com' }
    let(:options) { { headers: {} } }
    let(:response) { instance_double(Faraday::Response, body: '') }
    let(:connection) { instance_double(Faraday::Connection, get: response) }

    it 'uses Faraday for the request' do
      allow(Faraday).to receive(:new).with(options.merge(url: url)).and_return(connection)
      described_class.request_body_from_url(url, **options.merge(convert_json_to_xml: false))
      expect(response).to have_received(:body)
    end
  end
end
