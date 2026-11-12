# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Article::Enclosure do
  describe '.guess_content_type_from_url' do
    {
      'https://example.com/image.jpg' => 'image/jpeg',
      'https://example.com/image.png' => 'image/png',
      'https://example.com/image.gif' => 'image/gif',
      'https://example.com/image.svg' => 'image/svg+xml',
      'https://example.com/image.webp' => 'image/webp',
      'https://example.com/image' => 'application/octet-stream',
      'https://example.com/media/clip.mp4' => 'video/mp4',
      'https://example.com/media/clip.M4V' => 'video/mp4',
      'https://example.com/media/clip.ogv' => 'video/ogg',
      'https://example.com/media/clip.webm' => 'video/webm',
      'https://example.com/media/talk.m4a' => 'audio/mp4',
      'https://example.com/media/talk.mp3?download=1' => 'audio/mpeg',
      'https://example.com/media/talk.ogg' => 'audio/ogg',
      'https://example.com/media/talk.oga' => 'audio/ogg',
      'https://example.com/media/talk.opus' => 'audio/opus',
      'https://example.com/media/talk.aac' => 'audio/aac',
      'https://example.com/media/talk.wav' => 'audio/wav',
      'https://example.com/media/talk.flac' => 'audio/flac',
      'https://example.com/media/live.m3u8' => 'application/vnd.apple.mpegurl',
      'https://example.com/docs/report.pdf' => 'application/pdf',
      'https://img.example.net/wp-content/photo.jpg?quality=85&w=925&h=617&crop=1&resize=925,617' => 'image/jpeg'
    }.each_pair do |url, expected|
      it { expect(described_class.guess_content_type_from_url(Html2rss::Url.from_relative(url, 'https://example.com'))).to eq expected }
    end

    it 'returns a string default when the url is missing or unrecognized', :aggregate_failures do
      unknown = Html2rss::Url.from_absolute('https://example.com/file.notarealext')
      jpeg = described_class.guess_content_type_from_url(Html2rss::Url.from_absolute('https://example.com/a.jpg'))

      expect(described_class.guess_content_type_from_url(nil, default: 'image/jpeg')).to eq('image/jpeg')
      expect(described_class.guess_content_type_from_url(unknown, default: 'text/html')).to eq('text/html')
      expect(jpeg).to be_a(String)
    end
  end

  describe '.parse_size' do
    {
      '12345' => 12_345,
      12_345 => 12_345,
      '850 KB' => 850_000,
      '12.3 MB' => 12_300_000,
      '12.3MB' => 12_300_000,
      ' 1 gb ' => 1_000_000_000,
      '2 TB' => 2_000_000_000_000,
      '1 KiB' => 1024,
      '1.5 MiB' => 1_572_864,
      '1 GiB' => 1_073_741_824,
      '1 TiB' => 1_099_511_627_776,
      '512 B' => 512,
      '1 byte' => 1,
      '300 bytes' => 300,
      '0.4' => nil,
      '0 MB' => nil,
      '12,3 MB' => nil,
      '-5 MB' => nil,
      'MB' => nil,
      'large' => nil,
      '12 MB extra' => nil,
      'about 12 MB' => nil,
      '12 parsecs' => nil,
      '' => nil,
      nil => nil
    }.each_pair do |value, expected|
      it "parses #{value.inspect} to #{expected.inspect}" do
        expect(described_class.parse_size(value)).to eq(expected)
      end
    end
  end

  describe '.parse_duration' do
    {
      'PT1H2M3S' => 3723,
      'PT45M' => 2700,
      'PT90S' => 90,
      'PT2H' => 7200,
      'PT1M30.6S' => 91,
      'pt1m' => 60,
      ' PT5S ' => 5,
      'P1DT1S' => 86_401,
      'P2D' => 172_800,
      'PT0S' => nil,
      'PT0.4S' => nil,
      'PT' => nil,
      'P' => nil,
      'PT1H2M3' => nil,
      '1:02:03' => 3723,
      '01:02:03' => 3723,
      '45:30' => 2730,
      '75:00' => 4500,
      '2700' => 2700,
      2700 => 2700,
      '61.5' => 62,
      ' 0:00:05 ' => 5,
      '0:00' => nil,
      '1:2:3:4' => nil,
      ':30' => nil,
      '1:' => nil,
      '1:02:03.' => nil,
      '-30' => nil,
      '45 minutes' => nil,
      'xPT5S' => nil,
      'PT5Sx' => nil,
      '' => nil,
      nil => nil
    }.each_pair do |value, expected|
      it "parses #{value.inspect} to #{expected.inspect}" do
        expect(described_class.parse_duration(value)).to eq(expected)
      end
    end
  end

  describe 'media kind' do
    {
      'audio/mpeg' => [true, false, false, false],
      'Audio/MPEG' => [true, false, false, false],
      'audio/ogg; codecs=opus' => [true, false, false, false],
      'VIDEO/MP4' => [false, true, false, false],
      'image/jpeg' => [false, false, true, false],
      'IMAGE/PNG' => [false, false, true, false],
      'text/html' => [false, false, false, true],
      'Text/HTML; charset=utf-8' => [false, false, false, true],
      'text/x-php' => [false, false, false, true],
      'application/x-httpd-php' => [false, false, false, true],
      'text/asp' => [false, false, false, true],
      'text/aspdotnet' => [false, false, false, true],
      'text/x-jsp' => [false, false, false, true],
      'text/x-cgi' => [false, false, false, true],
      'text/x-coldfusion' => [false, false, false, true],
      'application/xhtml+xml' => [false, false, false, true],
      'Application/XHTML+XML' => [false, false, false, true],
      'text/plain' => [false, false, false, false],
      'text/vtt' => [false, false, false, false],
      'application/pdf' => [false, false, false, false],
      'application/zip' => [false, false, false, false],
      '' => [false, false, false, false]
    }.each_pair do |type, (audio, video, image, page)|
      it "classifies #{type} as audio=#{audio} video=#{video} image=#{image} page=#{page}", :aggregate_failures do
        enclosure = described_class.new(url: Html2rss::Url.from_absolute('https://example.com/file'), type:)

        expect([enclosure.audio?, enclosure.video?, enclosure.media?]).to eq([audio, video, audio || video])
        expect(enclosure.image?).to be(image)
        expect(enclosure.page?).to be(page)
      end
    end

    it 'classifies by the type guessed from the URL' do
      enclosure = described_class.new(url: Html2rss::Url.from_absolute('https://example.com/episode.mp3'))

      expect(enclosure.media?).to be(true)
    end

    {
      ['notes.pdf', 'application/pdf'] => true,
      ['files.zip', nil] => true,
      ['download.bin', 'application/octet-stream'] => true,
      ['download.bin', nil] => true,
      ['download/42', 'application/pdf'] => true,
      ['watch/42', 'application/octet-stream'] => false,
      ['watch/44', 'Application/Octet-Stream'] => false,
      ['watch/42', nil] => false,
      ['player.swf', 'application/x-shockwave-flash'] => false,
      ['live/master.m3u8', nil] => false,
      ['live/master', 'application/vnd.apple.mpegurl'] => false,
      ['live/index.m3u8', 'Application/X-MPEGURL'] => false,
      ['live/manifest.mpd', 'application/dash+xml'] => false,
      ['episode.mp3', 'audio/mpeg'] => false,
      ['cover.jpg', nil] => false,
      ['embed/1', 'text/html'] => false,
      ['play.php', nil] => false,
      ['page.aspx', nil] => false,
      ['notes.txt', nil] => true,
      ['data.csv', nil] => true,
      ['event.ics', nil] => true,
      ['captions.vtt', nil] => true,
      ['data.csv', 'text/csv; charset=utf-8'] => true
    }.each_pair do |(path, type), document|
      it "classifies #{path} typed #{type.inspect} as document=#{document}" do
        enclosure = described_class.new(url: Html2rss::Url.from_absolute("https://example.com/#{path}"), type:)

        expect(enclosure.document?).to be(document)
      end
    end

    {
      ['episode.mp3', nil] => true,
      ['cover.jpg', nil] => true,
      ['notes.pdf', nil] => true,
      ['download/42', nil] => false,
      ['embed/1', 'text/html'] => false,
      ['player.swf', nil] => false,
      ['live/index.m3u8', nil] => false,
      ['live/manifest.mpd', 'application/dash+xml'] => false
    }.each_pair do |(path, type), file|
      it "classifies #{path} typed #{type.inspect} as file=#{file}" do
        enclosure = described_class.new(url: Html2rss::Url.from_absolute("https://example.com/#{path}"), type:)

        expect(enclosure.file?).to be(file)
      end
    end

    {
      'https://example.com/notes.pdf' => true,
      'https://example.com/watch/42' => false,
      'https://example.com/watch?v=42.mp4' => false,
      'https://example.com/' => false
    }.each_pair do |url, extension|
      it "sees a file extension in #{url}: #{extension}" do
        expect(described_class.new(url: Html2rss::Url.from_absolute(url)).file_extension?).to be(extension)
      end
    end

    {
      ['watch/42', nil, nil] => [true, false],
      ['watch/42', 'Application/Octet-Stream', nil] => [true, false],
      ['embed/1', 'text/html', 2048] => [true, false],
      ['story.html', nil, nil] => [true, false],
      ['download/42', nil, 2048] => [false, true],
      ['download/42', 'audio/mpeg', nil] => [false, false],
      ['download.bin', nil, nil] => [false, true],
      ['cover.jpg', nil, nil] => [false, false]
    }.each_pair do |(path, type, bytes_length), (player_page, document)|
      it "classifies #{path} typed #{type.inspect} of #{bytes_length.inspect} bytes as " \
         "player_page=#{player_page} document=#{document}",
         :aggregate_failures do
        enclosure = described_class.new(url: Html2rss::Url.from_absolute("https://example.com/#{path}"), type:,
                                        bytes_length:)

        expect(enclosure.player_page?).to be(player_page)
        expect(enclosure.document?).to be(document)
      end
    end
  end

  describe '#initialize' do
    subject { described_class.new(url:, type:, bytes_length:) }

    let(:url) { Html2rss::Url.from_absolute('https://example.com/image.jpg') }
    let(:type) { 'image/png' }
    let(:bytes_length) { 123 }

    it { expect(subject.url).to eq url }
    it { expect(subject.type).to eq type }
    it { expect(subject.bytes_length).to eq bytes_length }
    it { expect(subject.duration).to be_nil }

    context 'when the byte length is unknown' do
      let(:bytes_length) { nil }

      it { expect(subject.bytes_length).to eq 0 }
    end

    it 'rejects a missing, relative or non-http(s) URL', :aggregate_failures do
      expect { described_class.new(url: nil) }.to raise_error(ArgumentError, /absolute http\(s\) URL/)
      ['a.mp3', 'javascript:alert(1)//a.mp3', 'data:audio/mpeg;base64,AAAA', 'ftp://example.com/a.mp3'].each do |ref|
        expect { described_class.new(url: Html2rss::Url.from_relative(ref, '')) }
          .to raise_error(ArgumentError, /absolute http\(s\) URL/)
      end
    end

    it 'defaults the byte length to 0' do
      expect(described_class.new(url:).bytes_length).to eq 0
    end

    {
      3723 => 3723,
      1 => 1,
      0 => nil,
      -5 => nil,
      12.5 => nil,
      '60' => nil,
      nil => nil
    }.each_pair do |duration, expected|
      it "keeps duration #{duration.inspect} as #{expected.inspect}" do
        episode = Html2rss::Url.from_absolute('https://example.com/episode.mp3')

        expect(described_class.new(url: episode, duration:).duration).to eq(expected)
      end
    end

    {
      ['episode', 'audio/mpeg', nil] => 60,
      ['clip.webm', nil, nil] => 60,
      ['stream/42', nil, :video] => 60,
      ['transcript.pdf', nil, nil] => nil,
      ['cover.jpg', nil, nil] => nil,
      ['photo/42', nil, :image] => nil,
      ['live/index.m3u8', nil, :video] => nil,
      ['watch/42', nil, nil] => nil
    }.each_pair do |(path, type, kind), expected|
      it "keeps a duration on #{path} typed #{type.inspect} of kind #{kind.inspect} as #{expected.inspect}" do
        file = Html2rss::Url.from_absolute("https://example.com/#{path}")

        expect(described_class.new(url: file, type:, kind:, duration: 60).duration).to eq(expected)
      end
    end

    {
      ['https://example.com/photo/42', :image] => 'image/jpeg',
      ['https://example.com/thumb.php?id=1', :image] => 'image/jpeg',
      ['https://example.com/cover.png', :image] => 'image/png',
      ['https://example.com/clip.mp4', :image] => 'video/mp4',
      ['https://example.com/stream/42', :audio] => 'audio/mpeg',
      ['https://example.com/stream/42', :video] => 'video/mp4',
      ['https://example.com/play.php?id=1', :audio] => 'audio/mpeg',
      ['https://example.com/watch.aspx', :video] => 'video/mp4',
      ['https://example.com/clip.webm', :audio] => 'video/webm',
      ['https://example.com/live/index.m3u8', :video] => 'application/vnd.apple.mpegurl',
      ['https://example.com/cover.jpg', :video] => 'image/jpeg',
      ['https://example.com/stream/42', nil] => 'application/octet-stream',
      ['https://example.com/play.php', nil] => 'text/x-php'
    }.each_pair do |(file, kind), expected|
      it "types #{file} of kind #{kind.inspect} as #{expected}" do
        expect(described_class.new(url: Html2rss::Url.from_absolute(file), kind:).type).to eq(expected)
      end
    end

    it 'reads the declared type case-insensitively and without parameters', :aggregate_failures do
      expect(described_class.new(url:, type: 'Audio/MPEG; codecs=mp3', duration: 60).duration).to eq(60)
      expect(described_class.new(url:, type: 'text/html; charset=utf-8').file?).to be(false)
      expect(described_class.new(url:, type: '', duration: 60).duration).to be_nil
    end

    it 'keeps a declared type over the kind' do
      expect(described_class.new(url:, type: 'audio/ogg', kind: :video).type).to eq('audio/ogg')
    end

    it 'treats a declared untyped type as none only for a file of a known kind', :aggregate_failures do
      stream = Html2rss::Url.from_absolute('https://example.com/stream/42')
      expect(described_class.new(url: stream, type: 'Application/Octet-Stream', kind: :audio).type).to eq('audio/mpeg')
      expect(described_class.new(url:, type: 'application/octet-stream', kind: :video).type).to eq('image/jpeg')
      expect(described_class.new(url: stream, type: 'Application/Octet-Stream').type).to eq('Application/Octet-Stream')
    end

    it 'rejects an unknown kind', :aggregate_failures do
      expect { described_class.new(url:, kind: :page) }.to raise_error(ArgumentError, /Unknown enclosure kind: :page/)
      expect { described_class.new(url:, kind: 'audio') }.to raise_error(ArgumentError, /kind/)
    end

    context 'when URL is nil' do
      let(:url) { nil }

      it { expect { subject }.to raise_error(ArgumentError, 'An Enclosure requires an absolute http(s) URL') }
    end

    context 'when URL is relative' do
      let(:url) { Html2rss::Url.from_relative('/image.jpg', 'https://example.com') }

      it 'does not raise error' do
        expect { subject }.not_to raise_error
      end

      it 'resolves to absolute URL' do
        expect(subject.url.absolute?).to be true
      end
    end
  end
end
