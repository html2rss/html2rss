# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::BodyParser do
  subject(:parser) { described_class.new }

  describe '#parsed_body_for' do
    context 'with an HTML response' do
      let(:response) do
        Html2rss::RequestService::Response.new(
          url: 'http://example.com',
          headers: { 'content-type' => 'text/html' },
          body: '<html><body><article>one</article></body></html>'
        )
      end

      it 'returns the response document and caches by URL', :aggregate_failures do
        first = parser.parsed_body_for(response)
        second = parser.parsed_body_for(response)

        expect(first.at_css('article').text).to eq('one')
        expect(second).to equal(first)
      end
    end

    context 'with a JSON response' do
      let(:response) do
        Html2rss::RequestService::Response.new(
          url: 'http://example.com/api',
          headers: { 'content-type' => 'application/json' },
          body: '{"data":[{"title":"Headline"}]}'
        )
      end

      it 'converts JSON to an HTML5 fragment for CSS selection', :aggregate_failures do
        document = parser.parsed_body_for(response)

        expect(document).to be_a(Nokogiri::XML::DocumentFragment)
        expect(document.at_css('title').text).to eq('Headline')
      end
    end
  end
end
