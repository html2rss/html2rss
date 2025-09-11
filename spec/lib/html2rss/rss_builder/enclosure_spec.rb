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
      it { expect(described_class.guess_content_type_from_url(Html2rss::Url.from_relative(url, 'https://example.com'))).to eq expected }
    end
  end

  describe '#initialize' do
    subject { described_class.new(url:, type:, bits_length:) }

    let(:url) { Html2rss::Url.from_relative('https://example.com/image.jpg', 'https://example.com') }
    let(:type) { 'image/jpeg' }
    let(:bits_length) { 123 }

    it { expect(subject.url).to eq url }
    it { expect(subject.type).to eq type }
    it { expect(subject.bits_length).to eq bits_length }

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
