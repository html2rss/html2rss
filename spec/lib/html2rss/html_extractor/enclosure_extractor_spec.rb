# frozen_string_literal: true

RSpec.describe Html2rss::HtmlExtractor::EnclosureExtractor do
  describe '.call' do
    subject(:enclosures) { described_class.call(article_tag, base_url) }

    let(:base_url) { 'http://example.com' }

    # Helper method to create article tag from HTML
    def article_tag_from(html)
      Html2rss::HtmlParser.parse_html(html).at('article')
    end

    # Helper method to create expected enclosure hash
    def expected_enclosure(path, type)
      { url: Html2rss::Url.from_relative("http://example.com#{path}", 'http://example.com'), type: }
    end

    context 'when article_tag contains video and audio sources' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
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
          expected_enclosure('/videos/video1.mp4', 'video/mp4'),
          expected_enclosure('/videos/video2.webm', 'video/webm'),
          expected_enclosure('/audios/audio1.mp3', 'audio/mpeg')
        )
      end
    end

    context 'when article_tag contains no media sources' do
      let(:article_tag) { article_tag_from('<article><p>No media here</p></article>') }

      it 'returns an empty array' do
        expect(enclosures).to be_empty
      end
    end

    context 'when article_tag contains sources with empty src attributes' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
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
        article_tag_from(<<~HTML)
          <article>
            <a href="/documents/report.pdf">Download Report</a>
            <a href="/files/manual.pdf">Manual</a>
          </article>
        HTML
      end

      it 'extracts PDF enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure('/documents/report.pdf', 'application/pdf'),
          expected_enclosure('/files/manual.pdf', 'application/pdf')
        )
      end
    end

    context 'when article_tag contains iframe sources' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
          <article>
            <iframe src="/embeds/video.html"></iframe>
            <iframe src="/widgets/chart.html"></iframe>
          </article>
        HTML
      end

      it 'extracts iframe enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure('/embeds/video.html', 'text/html'),
          expected_enclosure('/widgets/chart.html', 'text/html')
        )
      end
    end

    context 'when article_tag contains archive links' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
          <article>
            <a href="/downloads/data.zip">Download ZIP</a>
            <a href="/archives/backup.tar.gz">Backup TAR.GZ</a>
            <a href="/files/package.tgz">Package TGZ</a>
          </article>
        HTML
      end

      it 'extracts archive enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure('/downloads/data.zip', 'application/zip'),
          expected_enclosure('/archives/backup.tar.gz', 'application/zip'),
          expected_enclosure('/files/package.tgz', 'application/zip')
        )
      end
    end

    context 'when article_tag contains PDF links with empty href attributes' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
          <article>
            <a href="">Empty PDF Link</a>
            <a href="/documents/valid.pdf">Valid PDF</a>
          </article>
        HTML
      end

      it 'ignores links with empty href attributes' do
        expect(enclosures).to contain_exactly(
          expected_enclosure('/documents/valid.pdf', 'application/pdf')
        )
      end
    end

    context 'when article_tag contains images' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
          <article>
            <img src="/images/photo.jpg" alt="Photo">
            <img src="/gallery/image.png" alt="Gallery Image">
          </article>
        HTML
      end

      it 'extracts image enclosures with correct URLs and types' do
        expect(enclosures).to contain_exactly(
          expected_enclosure('/images/photo.jpg', 'image/jpeg'),
          expected_enclosure('/gallery/image.png', 'image/png')
        )
      end
    end

    context 'when article_tag contains mixed content types' do
      let(:article_tag) do
        article_tag_from(<<~HTML)
          <article>
            <img src="/images/hero.jpg" alt="Hero">
            <video>
              <source src="/videos/demo.mp4" type="video/mp4">
            </video>
            <a href="/documents/guide.pdf">Guide</a>
            <iframe src="/widgets/map.html"></iframe>
            <a href="/downloads/source.zip">Source Code</a>
          </article>
        HTML
      end

      let(:expected_enclosures) do
        [
          expected_enclosure('/images/hero.jpg', 'image/jpeg'),
          expected_enclosure('/videos/demo.mp4', 'video/mp4'),
          expected_enclosure('/documents/guide.pdf', 'application/pdf'),
          expected_enclosure('/widgets/map.html', 'text/html'),
          expected_enclosure('/downloads/source.zip', 'application/zip')
        ]
      end

      it 'extracts all types of enclosures' do
        expect(enclosures).to match_array(expected_enclosures)
      end
    end
  end
end
