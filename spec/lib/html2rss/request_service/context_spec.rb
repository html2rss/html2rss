# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Context do
  specify { expect(described_class::SUPPORTED_URL_SCHEMES).to be_a(Set) & be_frozen }

  describe '#initialize' do
    subject(:instance) { described_class.new(url:) }

    let(:url) { Html2rss::Url.from_relative('http://example.com', 'http://example.com') }

    context 'with a valid URL (String)' do
      let(:url) { 'http://www.example.com' }

      it 'does not raise an error' do
        expect { instance }.not_to raise_error
      end
    end

    context 'with a valid URL (Html2rss::Url)' do
      it 'does not raise an error' do
        expect { instance }.not_to raise_error
      end
    end

    context 'with an invalid URL' do
      let(:url) { '12_345' }

      it 'raises an ArgumentError' do
        expect do
          instance
        end.to raise_error(Html2rss::RequestService::InvalidUrl, /URL must be absolute/)
      end
    end

    context 'when the URL is not absolute' do
      let(:url) { '/relative/path' }

      it 'raises an ArgumentError' do
        expect do
          instance
        end.to raise_error(Html2rss::RequestService::InvalidUrl, 'URL must be absolute')
      end
    end

    context 'when url contains userinfo' do
      ['https://user:pass@example.com',
       'https://example.com/foo?:/@https://www.youtube.com/watch?v=dQw4w9WgXcQ'].each do |url|
        let(:url) { url }

        it do
          expect do
            instance
          end.to raise_error(Html2rss::RequestService::InvalidUrl, /URL must not contain an @ character/)
        end
      end
    end

    context 'with an unsupported URL scheme' do
      let(:url) { 'ftp://www.example.com' }

      it 'raises an UnsupportedUrlScheme error' do
        expect do
          instance
        end.to raise_error(Html2rss::RequestService::UnsupportedUrlScheme, /not supported/)
      end
    end
  end
end
