# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::Thing do
  subject(:instance) { described_class.new(schema_object, url: 'https://example.com') }

  let(:schema_object) do
    { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation' }
  end

  specify { expect(described_class::SUPPORTED_TYPES).to be_a(Set) }

  describe '#call' do
    subject(:call) { instance.call }

    it 'sets the title' do
      expect(call).to include(title: 'Baustellen der Nation')
    end
  end

  describe '#id' do
    subject(:id) { instance.id }

    context 'when schema_object contains an @id' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', '@id': 'https://example.com/123' }
      end

      it 'returns the @id' do
        expect(id).to eq('https://example.com/123')
      end
    end

    context 'when schema_object does not contain an @id or URL' do
      let(:schema_object) { { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation' } }

      it 'returns nil' do
        expect(id).to be_nil
      end
    end
  end

  describe '#image' do
    subject(:image) { instance.image }

    context 'when image is a string' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: '/image.jpg' }
      end

      it 'returns the absolute image URL' do
        expect(image.to_s).to eq('https://example.com/image.jpg')
      end
    end

    context 'when image is an ImageObject' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: { '@type': 'ImageObject', url: 'http://example.com/image.jpg' } }
      end

      it 'returns the image URL from the ImageObject' do
        expect(image.to_s).to eq('http://example.com/image.jpg')
      end
    end

    context 'when image is an ImageObject with contentUrl' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: { '@type': 'ImageObject', contentUrl: 'http://example.com/image.jpg' } }
      end

      it 'returns the contentUrl from the ImageObject' do
        expect(image.to_s).to eq('http://example.com/image.jpg')
      end
    end

    context 'when image is a String' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: 'http://example.com/image1.jpg' }
      end

      it 'returns the first image URL' do
        expect(image.to_s).to eq('http://example.com/image1.jpg')
      end
    end

    context 'when thumbnailUrl is a String' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', thumbnailUrl: 'http://example.com/image1.jpg' }
      end

      it 'returns the first image URL' do
        expect(image.to_s).to eq('http://example.com/image1.jpg')
      end
    end

    context 'when image is nil' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', image: nil }
      end

      it 'returns nil' do
        expect(image).to be_nil
      end
    end
  end

  describe '#categories' do
    subject(:categories) { instance.categories }

    context 'when schema_object has keywords as array' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: %w[Politics Society Analysis] }
      end

      it 'returns the keywords as categories' do
        expect(categories).to eq(%w[Politics Society Analysis])
      end
    end

    context 'when schema_object has keywords as string' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: 'Politics, Society, Analysis' }
      end

      it 'splits keywords by comma and returns as categories' do
        expect(categories).to eq(%w[Politics Society Analysis])
      end
    end

    context 'when schema_object has categories field' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', categories: %w[News Technology] }
      end

      it 'returns the categories' do
        expect(categories).to eq(%w[News Technology])
      end
    end

    context 'when schema_object has tags field' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', tags: %w[Science Research] }
      end

      it 'returns the tags as categories' do
        expect(categories).to eq(%w[Science Research])
      end
    end

    context 'when schema_object has about field with objects' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation',
          about: [{ name: 'Politics' }, { name: 'Society' }] }
      end

      it 'extracts names from about objects' do
        expect(categories).to eq(%w[Politics Society])
      end
    end

    context 'when schema_object has mixed category sources' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: ['Politics'], categories: ['Society'],
          tags: 'Science, Research' }
      end

      it 'combines all category sources' do
        expect(categories).to eq(%w[Politics Society Science Research])
      end
    end

    context 'when schema_object has no category fields' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation' }
      end

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end

    context 'when schema_object has empty category fields' do
      let(:schema_object) do
        { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation', keywords: [], categories: '', tags: nil }
      end

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end
  end
end
