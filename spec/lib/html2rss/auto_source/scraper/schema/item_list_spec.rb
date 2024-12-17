# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::ItemList do
  subject(:instance) { described_class.new(schema_object, url: nil) }

  let(:schema_object) do
    {
      '@context': 'https://schema.org',
      '@type': 'ItemList',
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

    it 'returns an array of hashes' do
      expect(call).to be_an(Array)
    end

    it 'includes the correct number of items' do
      expect(call.size).to eq(3)
    end

    it 'sets the title' do
      expect(call).to include(
        hash_including(id: '/breakdancerin-raygun-geht-weiter-110168077.html'),
        hash_including(id: '/in-frankfurt-macht-die-neue-grundsteuer-das-wohnen-noch-teurer-110165876.html')
      )
    end

    context 'when the schema_object does not contain itemListElement' do
      let(:schema_object) { {} }

      it 'returns an array with one hash' do
        expect(call).to contain_exactly(an_instance_of(Hash))
      end
    end
  end
end
