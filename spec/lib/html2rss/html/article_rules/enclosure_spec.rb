# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Enclosure do
  let(:base_url) { 'https://example.com' }

  describe '.archive_href?' do
    it { expect(described_class.archive_href?('/a.pdf')).to be(true) }
    it { expect(described_class.archive_href?('/story')).to be(false) }
    it { expect(described_class.archive_href?(nil)).to be(false) }
  end

  describe '.from_element' do
    let(:enclosure_for) do
      lambda do |name, src: nil, href: nil, type: nil, in_player: false|
        found = described_class.from_element(name, base_url, src:, href:, type:) { in_player }
        found && { url: found[:url].to_s, type: found[:type] }
      end
    end

    it 'turns an image into an image enclosure typed from its extension', :aggregate_failures do
      expect(enclosure_for.call('img', src: '/hero.png')).to eq(url: 'https://example.com/hero.png', type: 'image/png')
      expect(enclosure_for.call('img', src: '/hero')).to eq(url: 'https://example.com/hero', type: 'image/jpeg')
    end

    it 'skips inline data and blank images', :aggregate_failures do
      expect(enclosure_for.call('img', src: 'data:image/png;base64,AAAA')).to be_nil
      expect(enclosure_for.call('img', src: ' ')).to be_nil
      expect(enclosure_for.call('img')).to be_nil
    end

    it 'turns audio and video players with a src into media enclosures keeping their type', :aggregate_failures do
      expect(enclosure_for.call('audio', src: '/a.mp3')).to eq(url: 'https://example.com/a.mp3', type: nil)
      expect(enclosure_for.call('video', src: '/v.bin', type: 'video/mp4'))
        .to eq(url: 'https://example.com/v.bin', type: 'video/mp4')
      expect(enclosure_for.call('video')).to be_nil
    end

    it 'turns a source into a media enclosure only inside an audio or video player', :aggregate_failures do
      expect(enclosure_for.call('source', src: '/a.ogg', type: 'audio/ogg', in_player: true))
        .to eq(url: 'https://example.com/a.ogg', type: 'audio/ogg')
      expect(enclosure_for.call('source', src: '/v.webm', in_player: true))
        .to eq(url: 'https://example.com/v.webm', type: nil)
      expect(enclosure_for.call('source', src: '/p.jpg')).to be_nil
    end

    it 'asks whether it sits inside a player only for a source element' do
      expect { |probe| described_class.from_element('audio', base_url, src: '/a.mp3', href: nil, type: nil, &probe) }
        .not_to yield_control
    end

    it 'turns file links into typed enclosures', :aggregate_failures do
      expect(enclosure_for.call('a', href: '/doc.pdf'))
        .to eq(url: 'https://example.com/doc.pdf', type: 'application/pdf')
      expect(enclosure_for.call('a', href: '/bundle.tgz'))
        .to eq(url: 'https://example.com/bundle.tgz', type: 'application/zip')
    end

    it 'ignores links to pages, embed frames and other elements', :aggregate_failures do
      expect(enclosure_for.call('a', href: '/news/story')).to be_nil
      expect(enclosure_for.call('a')).to be_nil
      expect(enclosure_for.call('iframe', src: '/embed/player')).to be_nil
      expect(enclosure_for.call('embed', src: '/a.mp3')).to be_nil
    end
  end

  describe '.from_media' do
    it 'keeps the declared type and resolves the url', :aggregate_failures do
      found = described_class.from_media('/a.mp3', 'audio/mpeg', base_url)
      expect(found[:url].to_s).to eq('https://example.com/a.mp3')
      expect(found[:type]).to eq('audio/mpeg')
      expect(described_class.from_media('', 'audio/mpeg', base_url)).to be_nil
      expect(described_class.from_media(nil, 'audio/mpeg', base_url)).to be_nil
    end
  end
end
