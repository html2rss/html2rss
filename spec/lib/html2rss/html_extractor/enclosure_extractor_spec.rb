# frozen_string_literal: true

require 'nokogiri'
require 'addressable/uri'

RSpec.describe Html2rss::HtmlExtractor::EnclosureExtractor do
  describe '.call' do
    subject(:enclosures) { described_class.call(article_tag, url) }

    let(:url) { 'http://example.com' }

    context 'when article_tag contains video and audio sources' do
      let(:html) do
        <<-HTML
          <article>
            <video>
              <source src="/videos/video1.mp4" type="video/mp4">
              <source src="/videos/video2.webm" type="video/webm">
            </video>
            <audio src="/audios/audio1.mp3" type="audio/mpeg"></audio>
          </article>
        HTML
      end
      let(:article_tag) { Nokogiri::HTML(html).at('article') }

      it 'extracts the enclosures with correct URLs and types', :aggregate_failures do
        expect(enclosures).to contain_exactly(
          { url: Addressable::URI.parse('http://example.com/videos/video1.mp4'), type: 'video/mp4' },
          { url: Addressable::URI.parse('http://example.com/videos/video2.webm'), type: 'video/webm' },
          { url: Addressable::URI.parse('http://example.com/audios/audio1.mp3'), type: 'audio/mpeg' }
        )
      end
    end

    context 'when article_tag contains no video or audio sources' do
      let(:html) { '<article><p>No media here</p></article>' }
      let(:article_tag) { Nokogiri::HTML(html).at('article') }

      it 'returns an empty array' do
        expect(enclosures).to be_empty
      end
    end

    context 'when article_tag contains sources with empty src attributes' do
      let(:html) do
        <<-HTML
          <article>
            <video>
              <source src="" type="video/mp4">
            </video>
            <audio src="" type="audio/mpeg"></audio>
          </article>
        HTML
      end
      let(:article_tag) { Nokogiri::HTML(html).at('article') }

      it 'ignores sources with empty src attributes' do
        expect(enclosures).to be_empty
      end
    end
  end
end
