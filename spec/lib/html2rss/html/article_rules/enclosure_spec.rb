# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Enclosure do
  let(:base_url) { 'https://example.com' }

  describe '.from_element' do
    let(:enclosure_for) do
      lambda do |name, src: nil, href: nil, type: nil, player: nil|
        found = described_class.from_element(name, base_url, src:, href:, type:) { player }
        found&.merge(url: found[:url].to_s)
      end
    end

    it 'turns an image into an image enclosure typed from its extension', :aggregate_failures do
      expect(enclosure_for.call('img', src: '/hero.png')).to eq(url: 'https://example.com/hero.png', type: 'image/png')
      expect(enclosure_for.call('img', src: '/hero')).to eq(url: 'https://example.com/hero', type: 'image/jpeg')
    end

    it 'skips inline data, blob and blank images', :aggregate_failures do
      expect(enclosure_for.call('img', src: 'data:image/png;base64,AAAA')).to be_nil
      expect(enclosure_for.call('img', src: 'blob:https://example.com/x')).to be_nil
      expect(enclosure_for.call('img', src: ' ')).to be_nil
      expect(enclosure_for.call('img')).to be_nil
    end

    it 'turns audio and video players with a src into media enclosures of their kind', :aggregate_failures do
      expect(enclosure_for.call('audio', src: '/a.mp3')).to eq(url: 'https://example.com/a.mp3', kind: :audio)
      expect(enclosure_for.call('video', src: '/v.bin', type: 'video/mp4'))
        .to eq(url: 'https://example.com/v.bin', type: 'video/mp4', kind: :video)
      expect(enclosure_for.call('video')).to be_nil
    end

    it 'turns a source into a media enclosure of its player kind only inside a player', :aggregate_failures do
      expect(enclosure_for.call('source', src: '/a.ogg', type: 'audio/ogg', player: 'audio'))
        .to eq(url: 'https://example.com/a.ogg', type: 'audio/ogg', kind: :audio)
      expect(enclosure_for.call('source', src: '/v', player: 'video'))
        .to eq(url: 'https://example.com/v', kind: :video)
      expect(enclosure_for.call('source', src: '/p.jpg')).to be_nil
    end

    it 'asks for the enclosing player only for a source element' do
      expect { |probe| described_class.from_element('audio', base_url, src: '/a.mp3', href: nil, type: nil, &probe) }
        .not_to yield_control
    end

    it 'turns file links into enclosures by URL path suffix, in any case and without the query', :aggregate_failures do
      expect(enclosure_for.call('a', href: '/doc.pdf')).to eq(url: 'https://example.com/doc.pdf')
      expect(enclosure_for.call('a', href: '/Bundle.TGZ?v=2')).to eq(url: 'https://example.com/Bundle.TGZ?v=2')
      expect(enclosure_for.call('a', href: '/b.tar.gz')).to eq(url: 'https://example.com/b.tar.gz')
      expect(enclosure_for.call('a', href: '/a.zip#top')).to eq(url: 'https://example.com/a.zip#top')
      expect(enclosure_for.call('a', href: '/read?file=a.pdf')).to be_nil
    end

    it 'turns audio and video file links into enclosures typed by their extension' do # rubocop:disable RSpec/ExampleLength
      typed = lambda do |href|
        enclosure = Html2rss::Article::Enclosure.new(**described_class.from_element('a', base_url, src: nil, href:,
                                                                                                   type: nil))
        [enclosure.url.path, enclosure.type]
      end
      expect(%w[/ep.mp3 /ep.m4a /clip.mp4 /EP.MP3 /ep.M4A?token=1 /ep.opus#t=10].map(&typed))
        .to eq([%w[/ep.mp3 audio/mpeg], %w[/ep.m4a audio/mp4], %w[/clip.mp4 video/mp4], %w[/EP.MP3 audio/mpeg],
                %w[/ep.M4A audio/mp4], %w[/ep.opus audio/opus]])
    end

    it 'ignores media names outside the path end and stream playlists', :aggregate_failures do
      %w[/play?file=ep.mp3 /ep.mp3x /ep.mp3/page /live.m3u8 /mp3].each do |href|
        expect(enclosure_for.call('a', href:)).to be_nil
      end
    end

    it 'ignores links to pages, non-web links, embed frames and other elements', :aggregate_failures do
      expect(enclosure_for.call('a', href: '/news/story')).to be_nil
      expect(enclosure_for.call('a', href: 'mailto:a@example.com?subject=a.pdf')).to be_nil
      expect(enclosure_for.call('a')).to be_nil
      expect(enclosure_for.call('iframe', src: '/embed/player')).to be_nil
      expect(enclosure_for.call('embed', src: '/a.mp3')).to be_nil
    end
  end

  describe '.file_link?' do
    it 'accepts document, archive and media file paths only', :aggregate_failures do
      expect(%w[/a.pdf /a.ZIP /a.tgz /a.mp3 /a.WEBM?x=1].map { described_class.file_link?(_1) }).to all(be(true))
      expect(['/a', '/a.html', '/a.jpg', '/?a.mp3', '', nil].map { described_class.file_link?(_1) }).to all(be(false))
    end
  end

  describe '.from_media' do
    it 'keeps the declared type and kind and resolves the url', :aggregate_failures do
      found = described_class.from_media('/a', 'audio/mpeg', base_url, kind: :audio)
      expect(found.merge(url: found[:url].to_s)).to eq(url: 'https://example.com/a', type: 'audio/mpeg', kind: :audio)
      expect(described_class.from_media('/a.mp3', nil, base_url).keys).to eq([:url])
    end

    ['', nil, ' ', 'javascript:void(0)', 'blob:https://example.com/x', 'data:audio/mpeg;base64,AA',
     'mailto:a@example.com', 'ftp://example.com/a.mp3', 'http://'].each do |src|
      it "rejects #{src.inspect}" do
        expect(described_class.from_media(src, 'audio/mpeg', base_url)).to be_nil
      end
    end

    it 'accepts an absolute http(s) URL without a base, but no relative one', :aggregate_failures do
      expect(described_class.from_media('/a.mp3', nil, nil)).to be_nil
      expect(described_class.from_media('HTTP://example.com/a.mp3', nil, nil)[:url].to_s).to eq('http://example.com/a.mp3')
    end
  end

  describe '.unique' do
    let(:url) { Html2rss::Url.from_absolute('https://example.com/v') }
    let(:other) { Html2rss::Url.from_absolute('https://example.com/w') }

    it 'keeps one entry per URL at its first position, preferring a declared type', :aggregate_failures do
      found = [{ url:, kind: :video }, { url: other }, { url:, type: 'video/webm', kind: :video },
               { url:, type: 'video/mp4' }]
      expect(described_class.unique(found)).to eq([{ url:, type: 'video/webm', kind: :video }, { url: other }])
      expect(described_class.unique([{ url: }, { url:, kind: :video }])).to eq([{ url: }])
    end

    it 'ships a download link and a player naming the same file once, at the first, typed by the player' do # rubocop:disable RSpec/ExampleLength
      found = [['a', { href: '/ep.mp3' }], ['img', { src: '/w.jpg' }],
               ['audio', { src: '/ep.mp3', type: 'audio/mpeg' }], ['a', { href: '/ep.mp3' }]].map do |name, attrs|
        described_class.from_element(name, base_url, src: nil, href: nil, type: nil, **attrs) { nil }
      end
      expect(described_class.unique(found).map { [_1[:url].path, _1[:type]] })
        .to eq([%w[/ep.mp3 audio/mpeg], %w[/w.jpg image/jpeg]])
    end
  end
end
