# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RssBuilder::Enclosure do
  describe '.guess_content_type_from_url(url)' do
    {
      'https://example.com/image.jpg' => 'image/jpeg',
      'https://example.com/image.png' => 'image/png',
      'https://example.com/image.gif' => 'image/gif',
      'https://example.com/image.svg' => 'image/svg+xml',
      'https://example.com/image.webp' => 'image/webp',
      'https://example.com/image' => 'application/octet-stream',
      'https://api.PAGE.com/wp-content/photo.jpg?quality=85&w=925&h=617&crop=1&resize=925,617' => 'image/jpeg'
    }.each_pair do |url, expected|
      it { expect(described_class.guess_content_type_from_url(Addressable::URI.parse(url))).to eq expected }
    end
  end

  describe '#initialize' do
    subject { described_class.new(url: url, type: type, bits_length: bits_length) }

    let(:url) { Addressable::URI.parse('https://example.com/image.jpg') }
    let(:type) { 'image/jpeg' }
    let(:bits_length) { 123 }

    it { expect(subject.url).to eq url }
    it { expect(subject.type).to eq type }
    it { expect(subject.bits_length).to eq bits_length }

    context 'when URL is nil' do
      let(:url) { nil }

      it { expect { subject }.to raise_error(ArgumentError, 'An Enclosure requires an absolute URL') }
    end

    context 'when URL is not absolute' do
      let(:url) { Addressable::URI.parse('/image.jpg') }

      it { expect { subject }.to raise_error(ArgumentError, 'An Enclosure requires an absolute URL') }
    end
  end
end
