# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::ItemList do
  subject(:instance) { described_class.new(schema_object, url: 'https://www.example.com') }

  let(:schema_object) do
    {
      '@context': 'https://schema.org',
      '@type': 'ItemList',
      name: 'Parent list (must not emit)',
      itemListElement: [
        {
          '@type': 'ListItem',
          position: 1,
          url: 'https://www.example.com/breakdancerin-raygun-geht-weiter-110168077.html'
        },
        {
          '@type': 'ListItem',
          position: 2,
          url: 'https://www.example.com/in-frankfurt-macht-die-neue-grundsteuer-das-wohnen-noch-teurer-110165876.html'
        }
      ]
    }
  end

  describe '#call' do
    subject(:call) { instance.call }

    it 'returns only list elements, not the ItemList parent', :aggregate_failures do
      expect(call.size).to eq(2)
      expect(call).to include(
        hash_including(id: '/breakdancerin-raygun-geht-weiter-110168077.html'),
        hash_including(id: '/in-frankfurt-macht-die-neue-grundsteuer-das-wohnen-noch-teurer-110165876.html')
      )
    end

    it 'does not emit the ItemList parent title' do
      expect(call).not_to include(hash_including(title: 'Parent list (must not emit)'))
    end

    it 'leaves URL-only ListItem stub titles empty instead of titleizing the path' do
      expect(call).to all(include(title: nil))
    end

    context 'when the schema_object does not contain itemListElement' do
      let(:schema_object) { { '@type': 'ItemList', name: 'Empty' } }

      it 'returns an empty array (container never emitted)' do
        expect(call).to eq([])
      end
    end

    context 'when the schema_object contains a single itemListElement' do
      let(:schema_object) do
        {
          '@context': 'https://schema.org',
          '@type': 'ItemList',
          itemListElement: {
            '@type': 'ListItem',
            position: 1,
            url: 'https://www.example.com/breakdancerin-raygun-geht-weiter-110168077.html'
          }
        }
      end

      it 'returns a single article hash' do
        expect(call).to contain_exactly(an_instance_of(Hash))
      end
    end

    context 'when ListItem wraps a nested Article item' do
      let(:schema_object) do
        {
          '@type': 'ItemList',
          itemListElement: [
            {
              '@type': 'ListItem',
              position: 1,
              item: {
                '@type': 'Article',
                '@id': 'https://www.example.com/nested-article',
                headline: 'Nested Article Headline',
                url: 'https://www.example.com/nested-article',
                description: 'Full article body in item'
              }
            }
          ]
        }
      end

      it 'unwraps item and emits the article' do
        expect(call).to contain_exactly(hash_including(title: 'Nested Article Headline', id: '/nested-article'))
      end
    end

    context 'when ListItem is a stub with @id and name' do
      let(:schema_object) do
        {
          '@type': 'ItemList',
          itemListElement: [
            {
              '@type': 'ListItem',
              item: { '@id': '123', name: 'Stub Item', url: 'https://www.example.com/stub' }
            }
          ]
        }
      end

      it 'emits the stub after ListItem unwrap', :aggregate_failures do
        expect(call.size).to eq(1)
        expect(call.first).to include(title: 'Stub Item', id: '123')
      end
    end

    context 'when itemListElement contains NewsArticle directly' do
      let(:schema_object) do
        {
          '@type': 'ItemList',
          itemListElement: [
            {
              '@type': 'NewsArticle',
              headline: 'Direct News',
              url: 'https://www.example.com/direct'
            }
          ]
        }
      end

      it 'emits article-shaped elements' do
        expect(call).to contain_exactly(hash_including(title: 'Direct News'))
      end
    end
  end
end
