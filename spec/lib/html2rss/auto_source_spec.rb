# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:instance) { described_class.new(url, body:, headers:) }

  let(:url) { Addressable::URI.parse('https://example.com') }
  let(:body) do
    '<html>
      <body>
        <article id="article-1">
          <h2>Article 1 <!-- remove this --></h2>
          <a href="/article1">Read more</a>
        </article>
        </body>
    </html>'
  end
  let(:headers) { {} }

  describe '#build' do
    let(:parsed_body) { Nokogiri::HTML.parse(response.body) }
    let(:articles) { [] }

    before do
      allow(Parallel).to receive(:map).and_return(articles)
    end

    context 'when articles are found' do
      let(:articles) do
        [
          described_class::Article.new(title: 'Article 1',
                                       url: Addressable::URI.parse('https://example.com/article1'),
                                       id: 'article-1',
                                       guid: '1qmp481',
                                       description: 'Read more',
                                       image: nil,
                                       scraper: Html2rss::AutoSource::Scraper::SemanticHtml)
        ]
      end

      before do
        allow(described_class::Reducer).to receive(:call)
        allow(described_class::Cleanup).to receive(:call)
        allow(Html2rss::RssBuilder).to receive(:new).and_return(instance_double(
                                                                  Html2rss::RssBuilder, call: nil
                                                                ))
      end

      it 'calls Reducer twice and Cleanup once', :aggregate_failures do
        instance.build

        expect(described_class::Reducer).to have_received(:call).with(articles, url:).at_least(:twice)
        expect(described_class::Cleanup).to have_received(:call).with(articles, url:, keep_different_domain: true).once
      end

      it 'calls RssBuilder with the correct arguments' do
        instance.build

        expect(Html2rss::RssBuilder).to have_received(:new).with(
          channel: instance_of(described_class::Channel), articles:, stylesheets: []
        )
      end
    end

    context 'when no articles are found' do
      let(:articles) { [] }

      it 'raises NoArticlesFound error' do
        expect { instance.build }.to raise_error(described_class::NoArticlesFound)
      end
    end
  end

  describe '#articles' do
    before do
      allow(Parallel).to receive(:flat_map)
        .and_yield(Html2rss::AutoSource::Scraper::SemanticHtml.new(parsed_body,
                                                                   url:).each)
    end

    let(:parsed_body) { Nokogiri::HTML.parse(body) }

    it 'returns a list of articles', :aggregate_failures do
      expect(instance.articles).to be_a(Array).and include(instance_of(described_class::Article))
    end
  end
end
