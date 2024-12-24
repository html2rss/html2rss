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
end
