# frozen_string_literal: true

RSpec.describe Html2rss::Item do
  describe '.categories' do
    subject(:instance) { described_class.send(:new, Nokogiri.HTML('<li> Category </li>'), config) }

    let(:config) do
      Html2rss::Config.new(
        channel: { url: 'http://example.com' },
        selectors: {
          items: {},
          foo: { selector: 'li' },
          bar: { selector: 'li' },
          categories: %i[foo bar]
        }
      )
    end

    it 'returns an array of uniq and stripped categories' do
      expect(instance.categories).to eq ['Category']
    end
  end

  describe '.enclosure' do
    subject(:instance) { described_class.send(:new, Nokogiri.HTML('<img src="http://example.com/image.jpg">'), config) }

    context 'when the enclosure URL is absolute' do
      let(:config) do
        Html2rss::Config.new(
          channel: { url: 'http://example.com' },
          selectors: {
            items: {},
            enclosure: { selector: 'img', extractor: 'attribute', attribute: 'src' }
          }
        )
      end

      it 'returns an Enclosure object with correct attributes', :aggregate_failures do
        enclosure = instance.enclosure

        expect(enclosure).to be_an_instance_of(Html2rss::Item::Enclosure)
        expect(enclosure.type).to eq('image/jpeg')
        expect(enclosure.url).to eq('http://example.com/image.jpg')
        expect(enclosure.bits_length).to eq(0)
      end
    end

    context 'when the enclosure specifies content_type' do
      let(:config) do
        Html2rss::Config.new(
          channel: { url: 'http://example.com' },
          selectors: {
            items: {},
            enclosure: { selector: 'img', extractor: 'attribute', attribute: 'src', content_type: 'image/webp' }
          }
        )
      end

      it 'returns an Enclosure object with the specified content_type', :aggregate_failures do
        enclosure = instance.enclosure

        expect(enclosure).to be_an_instance_of(Html2rss::Item::Enclosure)
        expect(enclosure.type).to eq('image/webp')
        expect(enclosure.url).to eq('http://example.com/image.jpg')
        expect(enclosure.bits_length).to eq(0)
      end
    end
  end
end
