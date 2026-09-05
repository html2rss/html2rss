# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedBuilder::ItemPresentation do
  describe '.description_for' do
    it 'renders via DescriptionBuilder from raw article fields' do
      article = Html2rss::Article.new(title: 'Sample instance', url: 'http://example.com', description: 'By John Doe')

      expect(described_class.description_for(article)).to include('By John Doe')
    end
  end

  describe '.rss_enclosure_for' do
    let(:audio_url) { Html2rss::Url.from_absolute('https://example.com/episode.mp3') }
    let(:image_url) { Html2rss::Url.from_absolute('https://example.com/cover.jpg') }

    it 'does not fall back to image when enclosures are absent' do
      article = Html2rss::Article.new(image: image_url)

      expect(described_class.rss_enclosure_for(article)).to be_nil
    end

    it 'skips image/* enclosures so RSS never uses an image as enclosure' do
      article = Html2rss::Article.new(
        enclosures: [{ url: image_url, type: 'image/jpeg' }],
        image: image_url
      )

      expect(described_class.rss_enclosure_for(article)).to be_nil
    end

    # rubocop:disable-next RSpec/ExampleLength -- prefers non-image enclosure while preserving image field
    it 'prefers the first non-image enclosure over image enclosures', :aggregate_failures do
      article = Html2rss::Article.new(
        enclosures: [
          { url: image_url, type: 'image/jpeg' },
          { url: audio_url, type: 'audio/mpeg' }
        ],
        image: image_url
      )
      enclosure = described_class.rss_enclosure_for(article)

      expect(enclosure.url).to eq(audio_url)
      expect(enclosure.type).to eq('audio/mpeg')
      expect(article.image).to eq(image_url)
    end
  end
end
