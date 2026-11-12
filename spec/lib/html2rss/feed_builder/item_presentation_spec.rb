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
    let(:files) do
      {
        'audio' => ['episode.mp3', 'audio/mpeg'], 'video' => ['clip.webm', 'video/webm'],
        'pdf' => ['notes.pdf', 'application/pdf'], 'zip' => ['files.zip', 'application/zip'],
        'image' => ['cover.jpg', 'image/jpeg'], 'html' => ['embed/1', 'text/html'],
        'xhtml' => ['embed/2', 'application/xhtml+xml']
      }
    end

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

    {
      'audio after a pdf' => [%w[pdf audio], 'audio'],
      'video after an archive' => [%w[zip video], 'video'],
      'the first of two media files' => [%w[pdf video audio], 'video'],
      'a pdf after an embed page' => [%w[html pdf], 'pdf'],
      'the first of two other files' => [%w[image zip pdf], 'zip'],
      'nothing for an embed page alone' => [%w[html], nil],
      'nothing for an xhtml page' => [%w[xhtml image], nil]
    }.each_pair do |label, (kinds, chosen)|
      it "chooses #{label}" do
        enclosures = kinds.map do |kind|
          { url: Html2rss::Url.from_absolute("https://example.com/#{files[kind][0]}"), type: files[kind][1] }
        end
        enclosure = described_class.rss_enclosure_for(Html2rss::Article.new(enclosures:))

        expect(enclosure&.type).to eq(chosen && files[chosen][1])
      end
    end
  end

  describe '.media_feed?' do
    let(:audio) { { url: Html2rss::Url.from_absolute('https://example.com/episode.mp3'), type: 'audio/mpeg' } }
    let(:pdf) { { url: Html2rss::Url.from_absolute('https://example.com/notes.pdf'), type: 'application/pdf' } }
    let(:image) { { url: Html2rss::Url.from_absolute('https://example.com/cover.jpg'), type: 'image/jpeg' } }

    it 'is false for an empty feed' do
      expect(described_class.media_feed?([])).to be(false)
    end

    it 'is true when more than half of the items carry audio or video' do
      articles = [[audio], [audio], [pdf]].map { |enclosures| Html2rss::Article.new(enclosures:) }

      expect(described_class.media_feed?(articles)).to be(true)
    end

    it 'is false when exactly half of the items carry audio or video' do
      articles = [[audio], [pdf, image]].map { |enclosures| Html2rss::Article.new(enclosures:) }

      expect(described_class.media_feed?(articles)).to be(false)
    end

    it 'counts an item whose media file follows other files' do
      articles = [Html2rss::Article.new(enclosures: [image, pdf, audio])]

      expect(described_class.media_feed?(articles)).to be(true)
    end

    it 'is false when no item carries audio or video' do
      articles = [Html2rss::Article.new(enclosures: [pdf]), Html2rss::Article.new]

      expect(described_class.media_feed?(articles)).to be(false)
    end
  end
end
