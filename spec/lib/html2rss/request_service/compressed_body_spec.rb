# frozen_string_literal: true

require 'spec_helper'
require 'brotli'
require 'stringio'
require 'zlib'

RSpec.describe Html2rss::RequestService::CompressedBody do
  subject(:decoded) { described_class.decode(body, headers:) }

  let(:html) { '<!DOCTYPE html><html><body><div>decoded stream</div></body></html>' }
  let(:headers) { {} }

  context 'when the body is empty' do
    let(:body) { '' }

    it 'returns the original body' do
      expect(decoded).to eq('')
    end
  end

  context 'when Content-Encoding is gzip' do
    let(:headers) { { 'Content-Encoding' => 'gzip' } }
    let(:body) do
      StringIO.new.tap { |io| Zlib::GzipWriter.wrap(io) { |gzip| gzip.write(html) } }.string
    end

    it 'inflates the labeled gzip body' do
      expect(decoded).to eq(html)
    end
  end

  context 'when Content-Encoding is zlib deflate' do
    let(:headers) { { 'content-encoding' => 'deflate' } }
    let(:body) { Zlib::Deflate.deflate(html) }

    it 'inflates the labeled deflate body' do
      expect(decoded).to eq(html)
    end
  end

  context 'when Content-Encoding is raw deflate' do
    let(:headers) { { 'content-encoding' => 'deflate' } }
    let(:body) do
      inflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
      inflater.deflate(html, Zlib::FINISH)
    ensure
      inflater.close
    end

    it 'inflates the Microsoft-style raw deflate body' do
      expect(decoded).to eq(html)
    end
  end

  context 'when Content-Encoding is br' do
    let(:headers) { { 'content-encoding' => 'br' } }
    let(:body) { Brotli.deflate(html) }

    it 'inflates the labeled brotli body' do
      expect(decoded).to eq(html)
    end
  end

  context 'when Content-Encoding is gzip but the body is not gzip' do
    let(:headers) { { 'content-encoding' => 'gzip', 'content-type' => 'application/octet-stream' } }
    let(:body) { 'not-gzip' }

    it 'returns the original body' do
      expect(decoded).to eq('not-gzip')
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
end
