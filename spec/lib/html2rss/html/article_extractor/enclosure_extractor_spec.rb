# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::ArticleExtractor::EnclosureExtractor do
  describe '.call' do
    subject(:enclosures) do
      described_class.call(article_tag, base_url).map do |attributes|
        enclosure = Html2rss::Article::Enclosure.new(**attributes)
        [enclosure.url.to_s, enclosure.type]
      end
    end

    let(:base_url) { 'http://example.com' }
    let(:article_tag_from) { ->(html) { Nokogiri::HTML(html).at('article') } }
    let(:expected_enclosure) { ->(path, type) { ["http://example.com#{path}", type] } }

    context 'when article_tag contains video and audio sources' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <video>
              <source src="/videos/video1.mp4" type="video/mp4">
              <source src="/videos/video2.webm" type="video/webm">
            </video>
            <audio src="/audios/audio1.mp3" type="audio/mpeg"></audio>
          </article>
        HTML
      end

      it 'extracts the enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure.call('/videos/video1.mp4', 'video/mp4'),
          expected_enclosure.call('/videos/video2.webm', 'video/webm'),
          expected_enclosure.call('/audios/audio1.mp3', 'audio/mpeg')
        )
      end
    end

    context 'when article_tag contains no media sources' do
      let(:article_tag) { article_tag_from.call('<article><p>No media here</p></article>') }

      it 'returns an empty array' do
        expect(enclosures).to be_empty
      end
    end

    context 'when article_tag contains sources with empty src attributes' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <video>
              <source src="" type="video/mp4">
            </video>
            <audio src="" type="audio/mpeg"></audio>
          </article>
        HTML
      end

      it 'ignores sources with empty src attributes' do
        expect(enclosures).to be_empty
      end
    end

    context 'when article_tag contains PDF links' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <a href="/documents/report.pdf">Download Report</a>
            <a href="/files/manual.pdf">Manual</a>
          </article>
        HTML
      end

      it 'extracts PDF enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure.call('/documents/report.pdf', 'application/pdf'),
          expected_enclosure.call('/files/manual.pdf', 'application/pdf')
        )
      end
    end

    context 'when article_tag contains embed player frames' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <iframe src="/embeds/video.html"></iframe>
            <iframe src="/embeds/clip.mp4"></iframe>
          </article>
        HTML
      end

      it 'never turns an iframe into an enclosure' do
        expect(enclosures).to be_empty
      end
    end

    context 'when article_tag contains a video player with its own src' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <video src="/videos/clip.mp4" poster="/posters/clip.jpg"></video>
            <picture><source src="/images/hero.webp" type="image/webp"></picture>
          </article>
        HTML
      end

      it 'extracts the video file and no picture source' do
        expect(enclosures).to eq([expected_enclosure.call('/videos/clip.mp4', 'video/mp4')])
      end
    end

    context 'when article_tag contains archive links' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <a href="/downloads/data.zip">Download ZIP</a>
            <a href="/archives/backup.tar.gz">Backup TAR.GZ</a>
            <a href="/files/package.tgz">Package TGZ</a>
          </article>
        HTML
      end

      it 'extracts archive enclosures typed from their extension' do
        expect(enclosures).to contain_exactly(
          expected_enclosure.call('/downloads/data.zip', 'application/zip'),
          expected_enclosure.call('/archives/backup.tar.gz', 'application/gzip'),
          expected_enclosure.call('/files/package.tgz', 'application/gzip')
        )
      end
    end

    context 'when file links differ in case or carry a query' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <a href="/documents/REPORT.PDF">Report</a>
            <a href="/downloads/data.zip?token=1">Data</a>
            <a href="/news/story?file=a.pdf">Story</a>
          </article>
        HTML
      end

      it 'matches the URL path in any case and ignores the query' do
        expect(enclosures).to eq([expected_enclosure.call('/documents/REPORT.PDF', 'application/pdf'),
                                  expected_enclosure.call('/downloads/data.zip?token=1', 'application/zip')])
      end
    end

    context 'when players name an untyped file without a media extension' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <video src="/stream/clip"></video>
            <audio><source src="/stream/episode"></audio>
            <audio src="/play.php?id=7"></audio>
            <video src="/live/index.m3u8"></video>
          </article>
        HTML
      end

      it 'types each file from its player, but keeps a stream playlist', :aggregate_failures do
        expect(enclosures).to eq([expected_enclosure.call('/stream/clip', 'video/mp4'),
                                  expected_enclosure.call('/stream/episode', 'audio/mpeg'),
                                  expected_enclosure.call('/play.php?id=7', 'audio/mpeg'),
                                  expected_enclosure.call('/live/index.m3u8', 'application/vnd.apple.mpegurl')])
      end
    end

    context 'when a player repeats its file in a typed source' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <video src="/stream/clip"><source src="/stream/clip" type="video/webm"></video>
            <video src="/v.mp4"><source src="/v.mp4"></video>
          </article>
        HTML
      end

      it 'keeps one enclosure per URL, the typed one' do
        expect(enclosures).to eq([expected_enclosure.call('/stream/clip', 'video/webm'),
                                  expected_enclosure.call('/v.mp4', 'video/mp4')])
      end
    end

    context 'when players and links name non-web URLs' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <video src="blob:https://example.com/x"></video>
            <audio src="javascript:void(0)"></audio>
            <video><source src="data:video/mp4;base64,AAAA"></video>
            <a href="mailto:a@example.com?subject=a.pdf">Mail</a>
            <a href="ftp://example.com/a.zip">FTP</a>
          </article>
        HTML
      end

      it 'turns none of them into an enclosure' do
        expect(enclosures).to be_empty
      end
    end

    context 'when article_tag contains PDF links with empty href attributes' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <a href="">Empty PDF Link</a>
            <a href="/documents/valid.pdf">Valid PDF</a>
          </article>
        HTML
      end

      it 'ignores links with empty href attributes' do
        expect(enclosures).to contain_exactly(
          expected_enclosure.call('/documents/valid.pdf', 'application/pdf')
        )
      end
    end

    context 'when article_tag contains images' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <img src="/images/photo.jpg" alt="Photo">
            <img src="/gallery/image.png" alt="Gallery Image">
          </article>
        HTML
      end

      it 'extracts image enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure.call('/images/photo.jpg', 'image/jpeg'),
          expected_enclosure.call('/gallery/image.png', 'image/png')
        )
      end
    end

    context 'when article_tag contains mixed content types' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <img src="/images/hero.jpg" alt="Hero">
            <video>
              <source src="/videos/demo.mp4" type="video/mp4">
            </video>
            <a href="/documents/guide.pdf">Guide</a>
            <iframe src="/widgets/map.html"></iframe>
            <a href="/news/story">Story</a>
            <a href="/downloads/source.zip">Source Code</a>
          </article>
        HTML
      end

      let(:expected_enclosures) do
        [
          expected_enclosure.call('/images/hero.jpg', 'image/jpeg'),
          expected_enclosure.call('/videos/demo.mp4', 'video/mp4'),
          expected_enclosure.call('/documents/guide.pdf', 'application/pdf'),
          expected_enclosure.call('/downloads/source.zip', 'application/zip')
        ]
      end

      it 'extracts images, media and file links in document order' do
        expect(enclosures).to eq(expected_enclosures)
      end
    end

    context 'when article_tag links its episode files, in noscript too, beside a player' do
      let(:article_tag) do
        article_tag_from.call(<<~HTML)
          <article>
            <a href="/audio/ep.MP3?src=list" download>Download</a>
            <noscript><p><a href="/video/ep.mp4">Watch offline</a></p></noscript>
            <audio src="/audio/ep.MP3?src=list" type="audio/mpeg"></audio>
          </article>
        HTML
      end

      it 'ships each file once, typed by its extension or declared type, in document order' do
        expect(enclosures).to eq([expected_enclosure.call('/audio/ep.MP3?src=list', 'audio/mpeg'),
                                  expected_enclosure.call('/video/ep.mp4', 'video/mp4')])
      end
    end
  end
end
