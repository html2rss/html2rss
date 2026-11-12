# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Syndication::ItemMedia do
  describe '.for_items' do
    subject(:media) do
      described_class.for_items(body, count:) do |raw|
        Html2rss::Url.from_relative(raw, 'https://example.com/feed/') if raw in String
      end
    end

    let(:count) { 1 }
    let(:enclosures) do
      media.map { |item| item.fetch(:enclosures, []).map { |file| file.merge(url: file[:url].to_s) } }
    end

    context 'with an RSS 2.0 enclosure and an item itunes:duration' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><link>https://example.com/e/1</link><itunes:duration>1:02:03</itunes:duration>
              <enclosure url="https://example.com/e/1.mp3" type="audio/mpeg" length="12345"/></item>
          </channel></rss>
        XML
      end

      it 'carries url, type, byte length and the item duration' do
        expect(enclosures).to eq([[{ url: 'https://example.com/e/1.mp3', type: 'audio/mpeg', bytes_length: 12_345,
                                     duration: 3723 }]])
      end
    end

    context 'with itunes:duration in MM:SS and in seconds' do
      let(:count) { 2 }
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><itunes:duration>45:30</itunes:duration><enclosure url="e/1.mp3"/></item>
            <item><itunes:duration>2700</itunes:duration><enclosure url="e/2.mp3"/></item>
          </channel></rss>
        XML
      end

      it 'parses both clock forms and resolves relative file URLs' do
        expect(enclosures).to eq([[{ url: 'https://example.com/feed/e/1.mp3', duration: 2730 }],
                                  [{ url: 'https://example.com/feed/e/2.mp3', duration: 2700 }]])
      end
    end

    context 'with media:content directly and inside media:group' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
               xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><media:content url="https://example.com/v.mp4" type="video/mp4" fileSize="2048" duration="90"/>
              <media:group><media:content url="https://example.com/a.m4a" type="audio/mp4" fileSize="1 KB"/>
                <media:content url="https://example.com/v.mp4" type="video/mp4"/></media:group>
              <itunes:duration>60</itunes:duration></item>
          </channel></rss>
        XML
      end

      it 'reads each file once in document order, its own duration before the item duration' do
        video = { url: 'https://example.com/v.mp4', type: 'video/mp4', bytes_length: 2048, duration: 90 }
        audio = { url: 'https://example.com/a.m4a', type: 'audio/mp4', bytes_length: 1000, duration: 60 }
        expect(enclosures).to eq([[video, audio]])
      end
    end

    context 'with blank or unusable attributes' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>C</title>
            <item><enclosure url=" " type="audio/mpeg"/>
              <enclosure href="https://example.com/b.mp3" url="" type=" " length="0"/>
              <media:content type="audio/mpeg"/></item>
          </channel></rss>
        XML
      end

      it 'skips files without a URL and omits a blank type, a zero size and an unknown duration' do
        expect(enclosures).to eq([[{ url: 'https://example.com/b.mp3' }]])
      end
    end

    context 'with Atom enclosure links' do
      let(:body) do
        <<~XML
          <feed xmlns="http://www.w3.org/2005/Atom"><entry><link rel="alternate" href="https://example.com/e/1"/>
            <link rel="enclosure" href="https://example.com/e/1.ogg" type="audio/ogg" length="777"/>
            <link rel="related" href="https://example.com/r"/></entry></feed>
        XML
      end

      it 'reads only rel="enclosure" links' do
        expect(enclosures).to eq([[{ url: 'https://example.com/e/1.ogg', type: 'audio/ogg', bytes_length: 777 }]])
      end
    end

    context 'with RSS 1.0 items' do
      let(:count) { 2 }
      let(:body) do
        <<~XML
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/"
                   xmlns:media="http://search.yahoo.com/mrss/"><channel><title>C</title><items/></channel>
            <item><media:content url="https://example.com/1.mp3"/></item><item/></rdf:RDF>
        XML
      end

      it 'reads the items beside the channel, in document order' do
        expect(enclosures).to eq([[{ url: 'https://example.com/1.mp3' }], []])
      end
    end

    context 'with item images' do
      let(:count) { 3 }
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
               xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><media:thumbnail url="https://example.com/t.jpg"/><itunes:image href="i.jpg"/></item>
            <item><itunes:image href=" "/><media:group><media:thumbnail url="https://example.com/g.jpg"/></media:group></item>
            <item/>
          </channel></rss>
        XML
      end

      it 'prefers itunes:image over media:thumbnail and has none without either' do
        images = media.map { _1[:image]&.to_s }
        expect(images).to eq(['https://example.com/feed/i.jpg', 'https://example.com/g.jpg', nil])
      end

      it 'carries only the keys an item has' do
        expect(media.map(&:keys)).to eq([[:image], [:image], []])
      end
    end

    context 'with media:content declaring a playable medium' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>C</title>
            <item><media:content url="https://example.com/watch/42" medium="video"/>
              <media:content url="https://example.com/listen/7" medium="audio" type="text/html"/>
              <media:content url="https://example.com/stream/9" medium="video" type="video/mp4"/>
              <media:content url="https://example.com/player.swf" medium="video"/>
              <media:content url="https://example.com/watch/43"/></item>
          </channel></rss>
        XML
      end

      it 'drops a watch or player page (no media file, no file extension) and keeps the rest' do
        expect(enclosures).to eq([[{ url: 'https://example.com/stream/9', type: 'video/mp4' },
                                   { url: 'https://example.com/player.swf' }, { url: 'https://example.com/watch/43' }]])
      end
    end

    context 'with image files and no declared item image' do
      let(:count) { 4 }
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
               xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><media:content url="https://example.com/a.mp4" medium="video"/>
              <media:content url="https://example.com/img/1" medium="image"/><media:content url="https://example.com/2.jpg"/></item>
            <item><enclosure url="https://example.com/3.png" type="image/png"/><media:content url="https://example.com/4.jpg"/></item>
            <item><media:content url="https://example.com/5.jpg"/><media:thumbnail url="https://example.com/t.jpg"/></item>
            <item><media:content url="https://example.com/6.jpg"/><itunes:image href="https://example.com/i.jpg"/>
              <media:thumbnail url="https://example.com/t2.jpg"/></item>
          </channel></rss>
        XML
      end

      it 'takes the first image file, after itunes:image and media:thumbnail', :aggregate_failures do
        expect(media.map { _1[:image]&.to_s }).to eq(%w[https://example.com/img/1 https://example.com/3.png
                                                        https://example.com/t.jpg https://example.com/i.jpg])
        expect(enclosures.first.map { _1[:url] }).to eq(%w[https://example.com/a.mp4 https://example.com/img/1
                                                           https://example.com/2.jpg])
      end
    end

    context 'when the item elements do not number the parsed items' do
      let(:count) { 2 }
      let(:body) { '<rss version="2.0"><channel><item><enclosure url="https://example.com/1.mp3"/></item></channel></rss>' }

      it 'gives every item no media' do
        expect(media).to eq([{}, {}])
      end
    end
  end
end
