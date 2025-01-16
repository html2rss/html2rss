# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors do
  subject(:instance) { described_class.new(response, selectors: selectors, time_zone: time_zone) }

  let(:response) { Html2rss::RequestService::Response.new url: 'http://example.com', headers: { 'content-type': 'text/html' }, body: }
  let(:selectors) do
    {
      items: { selector: 'article' },
      title: { selector: 'h1' }
    }
  end

  let(:time_zone) { 'UTC' }
  let(:body) do
    <<~HTML
      <html><body>
        <article><h1>article1</h1></article>
        <article><h1>article2</h1></article>
      </body></html>
    HTML
  end

  describe '#each' do
    it 'returns an Enumerator if no block is given' do
      expect(instance.each).to be_a(Enumerator)
    end

    it 'yields the articles to given block' do
      expect { |b| instance.each(&b) }.to yield_successive_args(
        Html2rss::RssBuilder::Article,
        Html2rss::RssBuilder::Article
      )
    end
  end

  describe '#articles' do
    subject(:titles) { instance.articles.map(&:title) }

    it 'returns the articles' do
      expect(titles).to eq(%w[article1 article2])
    end

    context 'when the order is set to reverse' do
      before { selectors[:items][:order] = 'reverse' }

      it 'reverses the articles' do
        expect(titles).to eq(%w[article2 article1])
      end
    end
  end

  context 'when title is static and description the html of <body>' do
    # Issue was reported at: https://github.com/html2rss/html2rss/issues/157
    let(:selectors) do
      {
        items: { selector: 'html' },
        title: { extractor: 'static', static: 'Test string' },
        description: { extractor: 'html', selector: 'body' }
      }
    end

    let(:body) do
      <<~HTML
        <html><body>
          <main>
            <h1>article1</h1>
            <script>alert('');</script>
          </main>
        </body></html>
      HTML
    end

    describe '#each' do
      it 'yields the articles with the static title and the sanitized <body> as description' do
        expect { |b| instance.each(&b) }.to yield_successive_args(
          an_object_having_attributes(title: 'Test string', description: %r{<main> <h1>article1</h1> </main>})
        )
      end
    end
  end
end
