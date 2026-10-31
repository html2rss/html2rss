# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema do
  describe '#each with @id references' do
    subject(:article) { described_class.new(Nokogiri::HTML(html), url: 'https://example.com').first }

    let(:graph) do
      {
        '@context': 'https://schema.org',
        '@graph': [
          { '@type': 'NewsArticle', headline: 'Ref', url: 'https://example.com/r', **references },
          { '@id': '#person', '@type': 'Person', name: 'Jane Doe' },
          { '@id': '#org', '@type': 'Organization', name: 'Example Org' },
          { '@id': '#img', '@type': 'ImageObject', url: 'https://example.com/i.jpg' }
        ]
      }
    end
    let(:html) { "<script type=\"application/ld+json\">#{graph.to_json}</script>" }

    context 'when author and image are stubs' do
      let(:references) { { author: { '@id': '#person' }, image: { '@id': '#img' } } }

      it 'resolves author and image from sibling nodes', :aggregate_failures do
        expect(article[:author]).to eq('Jane Doe')
        expect(article[:image].to_s).to eq('https://example.com/i.jpg')
      end
    end

    context 'when a publisher stub is given in a list' do
      let(:references) { { publisher: [{ '@id': '#org' }] } }

      it { expect(article[:author]).to eq('Example Org') }
    end

    context 'when the stub has no sibling node' do
      let(:references) { { author: { '@id': '#missing' } } }

      it { expect(article[:author]).to be_nil }
    end
  end
end
