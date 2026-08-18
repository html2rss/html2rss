# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Response do
  subject(:instance) { described_class.new(body:, headers:, url: Html2rss::Url.from_absolute('https://example.com')) }

  describe '#headers' do
    subject(:returned_headers) { instance.headers }

    let(:body) { nil }
    let(:headers) { { key: 42 } }

    it 'returns hash w/ string keys', :aggregate_failures do
      expect(returned_headers).to eq('key' => 42)
      expect(returned_headers).not_to be headers
    end
  end

  describe '#content_type' do
    let(:body) { '' }

    context 'when the response uses canonical header casing' do
      let(:headers) { { 'Content-Type' => 'text/html' } }

      it 'looks up the header case-insensitively' do
        expect(instance.content_type).to eq('text/html')
      end
    end
  end

  describe '#parsed_body' do
    subject(:parsed_body) { instance.parsed_body }

    context 'when the response is HTML' do
      let(:body) do
        <<-HTML
      <html>
        <body>
          <!-- This is a comment -->
          <div>Hello World</div>
        </body>
      </html>
        HTML
      end
      let(:headers) { { 'content-type' => 'text/html' } }

      it { expect(parsed_body).to be_frozen }

      it 'parses the body and removes comments', :aggregate_failures do
        expect(parsed_body.at_xpath('//comment()')).to be_nil
        expect(parsed_body.at_css('div').text).to eq('Hello World')
      end
    end

    context 'when the response is JSON' do
      let(:body) { '{"key": "value"}' }
      let(:headers) { { 'content-type' => 'application/json' } }

      it { expect(parsed_body).to be_frozen }

      it 'parses the body as JSON' do
        expect(parsed_body).to eq({ key: 'value' })
      end
    end

    context 'when the response content type is not supported' do
      let(:body) { 'Some unsupported content' }
      let(:headers) { { 'content-type' => 'text/plain' } }

      it 'raises an UnsupportedResponseContentType error' do
        expect do
          parsed_body
        end.to raise_error(Html2rss::RequestService::UnsupportedResponseContentType,
                           'Unsupported content type: text/plain')
      end
    end

    [
      { content_type: 'application/octet-stream', label: 'octet-stream' },
      { content_type: '', label: 'empty' },
      { content_type: 'text/plain', label: 'wrong' }
    ].each do |example|
      context "when Content-Type is #{example[:label]} but the body looks like HTML" do
        let(:body) { "<!DOCTYPE html><html><body><div>#{example[:label]}</div></body></html>" }
        let(:headers) { example[:content_type].empty? ? {} : { 'content-type' => example[:content_type] } }

        it 'parses the HTML document' do
          expect(parsed_body.at_css('div').text).to eq(example[:label])
        end
      end
    end

    context 'when Content-Type is octet-stream and the body is not HTML' do
      let(:body) { "PK\x03\x04not-html" }
      let(:headers) { { 'content-type' => 'application/octet-stream' } }

      it 'raises UnsupportedResponseContentType' do
        expect { parsed_body }
          .to raise_error(Html2rss::RequestService::UnsupportedResponseContentType,
                          'Unsupported content type: application/octet-stream')
      end
    end

    [
      {
        label: 'Content-Type charset',
        headers: { 'content-type' => 'text/html; charset=windows-1252' },
        html: '<!DOCTYPE html><html><body><h1>Caffè</h1></body></html>'
      },
      {
        label: 'meta charset',
        headers: { 'content-type' => 'text/html' },
        html: '<!DOCTYPE html><html><head><meta charset="windows-1252"></head>' \
              '<body><h1>Caffè</h1></body></html>'
      }
    ].each do |example|
      context "when windows-1252 HTML uses #{example[:label]}" do
        let(:body) { example[:html].encode('Windows-1252').force_encoding(Encoding::UTF_8) }
        let(:headers) { example[:headers] }

        it 'decodes Caffè instead of mojibake' do
          expect(parsed_body.at_css('h1').text).to eq('Caffè')
        end
      end
    end
  end

  describe '#url' do
    let(:body) { '' }
    let(:headers) { {} }

    it 'returns the request URL' do
      expect(instance.url.to_s).to eq('https://example.com/')
    end
  end

  describe '#captured_responses' do
    let(:body) { '' }
    let(:headers) { {} }

    it 'defaults to an empty frozen array', :aggregate_failures do
      expect(instance.captured_responses).to eq([])
      expect(instance.captured_responses).to be_frozen
    end

    it 'stores captured responses when provided', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      captured = [{ 'url' => 'https://api.example/items', 'body' => '[]' }]
      response = described_class.new(
        body: '',
        headers: {},
        url: Html2rss::Url.from_absolute('https://example.com'),
        captured_responses: captured
      )

      expect(response.captured_responses).to eq(captured)
      expect(response.captured_responses).to be_frozen
    end
  end
end
