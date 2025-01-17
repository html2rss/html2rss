# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Response do
  subject(:instance) { described_class.new(body:, headers:, url: Addressable::URI.parse('https://example.com')) }

  describe '#headers' do
    subject(:returned_headers) { instance.headers }

    let(:body) { nil }
    let(:headers) { { key: 42 } }

    it 'returns hash w/ string keys', :aggregate_failures do
      expect(returned_headers).to eq('key' => 42)
      expect(returned_headers).not_to be headers
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
  end
end
