# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Article::Enclosure do
  describe '.guess_content_type_from_url' do
    {
      'https://example.com/image.jpg' => 'image/jpeg',
      'https://example.com/image.png' => 'image/png',
      'https://example.com/image.gif' => 'image/gif',
      'https://example.com/image.svg' => 'image/svg+xml',
      'https://example.com/image.webp' => 'image/webp',
      'https://example.com/image' => 'application/octet-stream',
      'https://img.example.net/wp-content/photo.jpg?quality=85&w=925&h=617&crop=1&resize=925,617' => 'image/jpeg'
    }.each_pair do |url, expected|
      it { expect(described_class.guess_content_type_from_url(Html2rss::Url.from_relative(url, 'https://example.com'))).to eq expected }
    end

    it 'returns a string default when the url is missing or unrecognized', :aggregate_failures do
      unknown = Html2rss::Url.from_absolute('https://example.com/file.notarealext')
      jpeg = described_class.guess_content_type_from_url(Html2rss::Url.from_absolute('https://example.com/a.jpg'))

      expect(described_class.guess_content_type_from_url(nil, default: 'image/jpeg')).to eq('image/jpeg')
      expect(described_class.guess_content_type_from_url(unknown, default: 'text/html')).to eq('text/html')
      expect(jpeg).to be_a(String)
    end
  end

  describe '.parse_size' do
    {
      '12345' => 12_345,
      12_345 => 12_345,
      '850 KB' => 850_000,
      '12.3 MB' => 12_300_000,
      '12.3MB' => 12_300_000,
      ' 1 gb ' => 1_000_000_000,
      '2 TB' => 2_000_000_000_000,
      '1 KiB' => 1024,
      '1.5 MiB' => 1_572_864,
      '1 GiB' => 1_073_741_824,
      '1 TiB' => 1_099_511_627_776,
      '512 B' => 512,
      '1 byte' => 1,
      '300 bytes' => 300,
      '0.4' => nil,
      '0 MB' => nil,
      '12,3 MB' => nil,
      '-5 MB' => nil,
      'MB' => nil,
      'large' => nil,
      '12 MB extra' => nil,
      'about 12 MB' => nil,
      '12 parsecs' => nil,
      '' => nil,
      nil => nil
    }.each_pair do |value, expected|
      it "parses #{value.inspect} to #{expected.inspect}" do
        expect(described_class.parse_size(value)).to eq(expected)
      end
    end
  end

  describe '.parse_duration' do
    {
      'PT1H2M3S' => 3723,
      'PT45M' => 2700,
      'PT90S' => 90,
      'PT2H' => 7200,
      'PT1M30.6S' => 91,
      'pt1m' => 60,
      ' PT5S ' => 5,
      'P1DT1S' => 86_401,
      'P2D' => 172_800,
      'PT0S' => nil,
      'PT0.4S' => nil,
      'PT' => nil,
      'P' => nil,
      'PT1H2M3' => nil,
      '1:02:03' => 3723,
      '01:02:03' => 3723,
      '45:30' => 2730,
      '75:00' => 4500,
      '2700' => 2700,
      2700 => 2700,
      '61.5' => 62,
      ' 0:00:05 ' => 5,
      '0:00' => nil,
      '1:2:3:4' => nil,
      ':30' => nil,
      '1:' => nil,
      '1:02:03.' => nil,
      '-30' => nil,
      '45 minutes' => nil,
      'xPT5S' => nil,
      'PT5Sx' => nil,
      '' => nil,
      nil => nil
    }.each_pair do |value, expected|
      it "parses #{value.inspect} to #{expected.inspect}" do
        expect(described_class.parse_duration(value)).to eq(expected)
      end
    end
  end

  describe 'media kind' do
    {
      'audio/mpeg' => [true, false, false],
      'VIDEO/MP4' => [true, false, false],
      'image/jpeg' => [false, true, false],
      'IMAGE/PNG' => [false, true, false],
      'text/html' => [false, false, true],
      'Text/HTML' => [false, false, true],
      'text/x-php' => [false, false, true],
      'application/xhtml+xml' => [false, false, true],
      'Application/XHTML+XML' => [false, false, true],
      'application/pdf' => [false, false, false],
      'application/zip' => [false, false, false]
    }.each_pair do |type, (media, image, page)|
      it "classifies #{type} as media=#{media} image=#{image} page=#{page}", :aggregate_failures do
        enclosure = described_class.new(url: Html2rss::Url.from_absolute('https://example.com/file'), type:)

        expect(enclosure.media?).to be(media)
        expect(enclosure.image?).to be(image)
        expect(enclosure.page?).to be(page)
      end
    end

    it 'classifies by the type guessed from the URL' do
      enclosure = described_class.new(url: Html2rss::Url.from_absolute('https://example.com/episode.mp3'))

      expect(enclosure.media?).to be(true)
    end
  end

  describe '#initialize' do
    subject { described_class.new(url:, type:, bytes_length:) }

    let(:url) { Html2rss::Url.from_absolute('https://example.com/image.jpg') }
    let(:type) { 'image/png' }
    let(:bytes_length) { 123 }

    it { expect(subject.url).to eq url }
    it { expect(subject.type).to eq type }
    it { expect(subject.bytes_length).to eq bytes_length }
    it { expect(subject.duration).to be_nil }

    context 'when the byte length is unknown' do
      let(:bytes_length) { nil }

      it { expect(subject.bytes_length).to eq 0 }
    end

    it 'defaults the byte length to 0' do
      expect(described_class.new(url:).bytes_length).to eq 0
    end

    {
      3723 => 3723,
      1 => 1,
      0 => nil,
      -5 => nil,
      12.5 => nil,
      '60' => nil,
      nil => nil
    }.each_pair do |duration, expected|
      it "keeps duration #{duration.inspect} as #{expected.inspect}" do
        expect(described_class.new(url:, duration:).duration).to eq(expected)
      end
    end

    context 'when URL is nil' do
      let(:url) { nil }

      it { expect { subject }.to raise_error(ArgumentError, 'An Enclosure requires an absolute URL') }
    end

    context 'when URL is relative' do
      let(:url) { Html2rss::Url.from_relative('/image.jpg', 'https://example.com') }

      it 'does not raise error' do
        expect { subject }.not_to raise_error
      end

      it 'resolves to absolute URL' do
        expect(subject.url.absolute?).to be true
      end
    end
  end
end
