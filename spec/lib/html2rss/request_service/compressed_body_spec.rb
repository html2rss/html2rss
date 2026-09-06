# frozen_string_literal: true

require 'spec_helper'
require 'brotli'
require 'stringio'
require 'zlib'

RSpec.describe Html2rss::RequestService::CompressedBody do
  subject(:decoded) { described_class.decode(body, headers:) }

  let(:html) { '<!DOCTYPE html><html><body><div>decoded stream</div></body></html>' }
  let(:headers) { {} }

  it 'reuses Response::HTML_BODY_SNIFF instead of a lockstep copy' do
    expect(described_class::HTML_BODY_SNIFF).to equal(Html2rss::RequestService::Response::HTML_BODY_SNIFF)
  end

  context 'when the body is empty' do
    let(:body) { '' }

    it 'returns the original body' do
      expect(decoded).to eq('')
    end
  end

  context 'when body has unlabeled gzip magic bytes' do
    let(:body) do
      StringIO.new.tap { |io| Zlib::GzipWriter.wrap(io) { |gzip| gzip.write(html) } }.string
    end

    it 'inflates the unlabeled gzip body' do
      expect(decoded).to eq(html)
    end
  end

  context 'when body has unlabeled octet-stream brotli HTML' do
    let(:headers) { { 'content-type' => 'application/octet-stream' } }
    let(:body) { Brotli.deflate(html) }

    it 'inflates the unlabeled brotli HTML body' do
      expect(decoded).to eq(html)
    end
  end

  context 'when unlabeled octet-stream brotli is not HTML' do
    let(:headers) { { 'content-type' => 'application/octet-stream' } }
    let(:body) { Brotli.deflate('plain text payload') }

    it 'leaves the body unchanged' do
      expect(decoded).to eq(body)
    end
  end

  context 'when unlabeled octet-stream is not brotli' do
    let(:headers) { { 'content-type' => 'application/octet-stream' } }
    let(:body) { 'PK not a brotli stream' }

    it 'leaves the body unchanged' do
      expect(decoded).to eq(body)
    end
  end

  context 'when body is nil' do
    let(:body) { nil }

    it 'returns nil' do
      expect(decoded).to be_nil
    end
  end

  context 'when body has labeled content-encoding' do
    context 'with valid gzip encoding' do
      let(:headers) { { 'content-encoding' => 'gzip' } }
      let(:body) do
        StringIO.new.tap { |io| Zlib::GzipWriter.wrap(io) { |gzip| gzip.write(html) } }.string
      end

      it 'inflates the labeled gzip body' do
        expect(decoded).to eq(html)
      end
    end

    context 'with corrupted gzip encoding' do
      let(:headers) { { 'content-encoding' => 'gzip' } }
      let(:body) { 'not gzip' }

      it 'returns original body' do
        expect(decoded).to eq('not gzip')
      end
    end

    context 'with br encoding' do
      let(:headers) { { 'content-encoding' => 'br' } }
      let(:body) { Brotli.deflate('any content') }

      it 'inflates labeled brotli body without requiring html sniff' do
        expect(decoded).to eq('any content')
      end
    end

    context 'with deflate encoding (zlib wrapped)' do
      let(:headers) { { 'content-encoding' => 'deflate' } }
      let(:body) { Zlib::Deflate.deflate(html) }

      it 'inflates the deflate body' do
        expect(decoded).to eq(html)
      end
    end

    context 'with deflate encoding (raw deflate without header)' do
      let(:headers) { { 'content-encoding' => 'deflate' } }
      let(:body) do
        deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
        data = deflater.deflate(html, Zlib::FINISH)
        deflater.close
        data
      end

      it 'inflates the raw deflate body' do
        expect(decoded).to eq(html)
      end
    end
  end
end
