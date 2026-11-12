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

    context 'with watch or player pages among the files' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>C</title>
            <item><media:content url="https://example.com/watch/42" medium="video"/>
              <media:content url="https://example.com/listen/7" medium="audio" type="text/html"/>
              <media:content url="https://example.com/stream/9" medium="video" type="video/mp4"/>
              <media:content url="https://example.com/player.swf" medium="video"/>
              <media:content url="https://example.com/watch/43"/>
              <enclosure url="https://example.com/download/44" length="2048"/></item>
          </channel></rss>
        XML
      end

      it 'drops each page (web page, or untyped without extension and size) whatever its medium' do
        expect(enclosures).to eq([[{ url: 'https://example.com/stream/9', type: 'video/mp4', kind: :video },
                                   { url: 'https://example.com/player.swf', kind: :video },
                                   { url: 'https://example.com/download/44', bytes_length: 2048 }]])
      end
    end

    context 'with an untyped file declaring an audio or video medium' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
               xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><itunes:duration>90</itunes:duration>
              <media:content url="https://example.com/files/ep7" medium="audio" fileSize="1000" duration="60"/>
              <media:content url="https://example.com/files/clip8" medium="video" fileSize="2000"/>
              <media:content url="https://example.com/files/ep9.ogg" medium="video" fileSize="3000"/>
              <media:content url="https://example.com/files/ep10" medium="audio" type="audio/aac" fileSize="4000"/>
              <media:content url="https://example.com/files/ep11" medium="audio" type="Application/Octet-Stream"
                             fileSize="5000"/>
              <media:content url="https://example.com/files/ep12" type="audio/aac" fileSize="6000"/></item>
          </channel></rss>
        XML
      end

      let(:files) do
        media.first[:enclosures].map do |facts|
          [facts[:url].to_s, Html2rss::Article::Enclosure.new(**facts).type, facts[:duration]]
        end
      end

      it 'types it by the medium, keeping a declared type or a known extension, and gives it the item duration' do
        expect(files).to eq(
          [['https://example.com/files/ep7', 'audio/mpeg', 60], ['https://example.com/files/clip8', 'video/mp4', 90],
           ['https://example.com/files/ep9.ogg', 'audio/ogg', 90], ['https://example.com/files/ep10', 'audio/aac', 90],
           ['https://example.com/files/ep11', 'audio/mpeg', 90], ['https://example.com/files/ep12', 'audio/aac', 90]]
        )
      end
    end

    context 'with an item itunes:duration beside images and documents' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
               xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><itunes:duration>45:00</itunes:duration><enclosure url="https://example.com/a.mp3"/>
              <media:content url="https://example.com/a.jpg" medium="image"/>
              <media:content url="https://example.com/a.pdf" type="application/pdf"/>
              <media:content url="https://example.com/b.pdf" duration="30"/></item>
          </channel></rss>
        XML
      end

      it 'gives the item duration only to audio and video files' do
        expect(enclosures).to eq([[{ url: 'https://example.com/a.mp3', duration: 2700 },
                                   { url: 'https://example.com/a.jpg' },
                                   { url: 'https://example.com/a.pdf', type: 'application/pdf' },
                                   { url: 'https://example.com/b.pdf', duration: 30 }]])
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

    context 'with extension elements named item' do
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:x="urn:example:x" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>C</title>
            <x:item>extension</x:item><item><media:content url="https://example.com/1.mp3"/><x:item/></item>
          </channel><x:item/></rss>
        XML
      end

      it 'reads only the RSS 2.0 items' do
        expect(enclosures).to eq([[{ url: 'https://example.com/1.mp3' }]])
      end
    end

    context 'with Atom entries outside the Atom namespace' do
      let(:body) do
        <<~XML
          <feed xmlns="http://www.w3.org/2005/Atom" xmlns:x="urn:example:x"><x:entry/>
            <entry><link rel='enclosure' href="https://example.com/e/1.ogg"/></entry></feed>
        XML
      end

      it 'reads only the Atom entries, finding a single-quoted enclosure link' do
        expect(enclosures).to eq([[{ url: 'https://example.com/e/1.ogg' }]])
      end
    end

    context 'with an iTunes image written as element text' do
      let(:count) { 2 }
      let(:body) do
        <<~XML
          <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>C</title>
            <item><itunes:image> https://example.com/text.jpg </itunes:image></item>
            <item><itunes:image href="https://example.com/href.jpg">https://example.com/text.jpg</itunes:image></item>
          </channel></rss>
        XML
      end

      it 'takes the text URL, and the href when both are present' do
        expect(media.map { _1[:image].to_s }).to eq(%w[https://example.com/text.jpg https://example.com/href.jpg])
      end
    end

    context 'when the document declares no media' do
      let(:count) { 2 }
      let(:body) do
        <<~XML
          <rss version="2.0"><channel><title>C</title>
            <item><link>https://example.com/1</link></item><item><link>https://example.com/2</link></item>
          </channel></rss>
        XML
      end

      before { allow(Nokogiri).to receive(:XML).and_call_original }

      it 'gives every item no media without parsing the document again', :aggregate_failures do
        expect(media).to eq([{}, {}])
        expect(Nokogiri).not_to have_received(:XML)
      end
    end

    context 'when the item elements do not number the parsed items' do
      subject(:media) do
        described_class.for_items(body, count: 2, url: Html2rss::Url.from_absolute('https://example.com/feed.xml')) { nil }
      end

      let(:body) { '<rss version="2.0"><channel><item><enclosure url="https://example.com/1.mp3"/></item></channel></rss>' }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'gives every item no media and logs the mismatch with the feed URL', :aggregate_failures do
        expect(media).to eq([{}, {}])
        expect(Html2rss::Log).to have_received(:warn).with(
          { event_name: 'syndication.item_media_mismatch', feed_url: 'https://example.com/feed.xml',
            message: 'Syndication::ItemMedia: 1 item elements for 2 parsed items; no item media read' }.to_json
        )
      end
    end
  end
end
