# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

RSpec.describe Html2rss::Html::Rendering::DescriptionBuilder do
  describe '#call' do
    context 'when base is plain text' do
      subject(:description) { described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosure: nil, image: nil).call }

      let(:base) { 'By John Doe' }

      it 'returns the base description unchanged' do
        expect(description).to eq('By John Doe')
      end
    end

    context 'when base contains HTML' do
      subject(:description) do
        described_class.new(base:, title: 'Sample instance', url:, enclosure: nil, image: nil).call
      end

      let(:base) { '<b>Some bold text</b>' }
      let(:url) { 'http://example.com' }

      before do
        allow(Html2rss::Selectors::PostProcessors::SanitizeHtml).to receive(:call).with(base, url).and_call_original
      end

      it 'sanitizes the HTML', :aggregate_failures do
        expect(description).to eq('<b>Some bold text</b>')
        expect(Html2rss::Selectors::PostProcessors::SanitizeHtml).to have_received(:call).with(base, url)
      end
    end

    context 'when base starts with the title' do
      subject(:description) { described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosure: nil, image: nil).call }

      let(:base) { 'Sample instance By John Doe' }

      it 'removes the title from the start' do
        expect(description).to eq('By John Doe')
      end
    end

    context 'when base is nil' do
      subject(:description) { described_class.new(base: nil, title: 'Sample instance', url: 'http://example.com', enclosure: nil, image: nil).call }

      it 'returns nil' do
        expect(description).to be_nil
      end
    end

    context 'when base is empty' do
      subject(:description) { described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosure: nil, image: nil).call }

      let(:base) { '' }

      it 'returns nil' do
        expect(description).to be_nil
      end
    end
  end

  describe '#call media element' do
    subject(:doc) { Nokogiri::HTML.fragment(html) }

    let(:enclosure_for) do
      ->(file, type = nil) { Html2rss::Article::Enclosure.new(url: Html2rss::Url.from_absolute("http://example.com/#{file}"), type:) }
    end
    let(:base) { 'Caption' }
    let(:image) { nil }
    let(:enclosure) { nil }
    let(:html) do
      described_class.new(base:, title: 'Sample instance', url: 'http://example.com/post', enclosure:, image:).call
    end

    context 'with the item image only' do
      let(:image) { 'http://example.com/image.jpg' }

      it 'renders one <img> before the text', :aggregate_failures do
        img = doc.at_css('img')
        expect(doc.css('img, audio, video, iframe').size).to eq(1)
        expect([img['src'], img['alt'], img['title']])
          .to eq(['http://example.com/image.jpg', 'Sample instance', 'Sample instance'])
        expect(html).to end_with("\n\nCaption")
      end
    end

    context 'with a video enclosure and an image' do
      let(:enclosure) { enclosure_for.call('clip.webm', 'Video/WebM; codecs=vp9') }
      let(:image) { 'http://example.com/poster.jpg' }

      it 'renders only the <video> player', :aggregate_failures do
        expect(doc.css('img, audio, video').map(&:name)).to eq(['video'])
        expect(doc.at_css('video source').to_h.slice('src', 'type'))
          .to eq('src' => 'http://example.com/clip.webm', 'type' => 'Video/WebM; codecs=vp9')
      end
    end

    context 'with an audio enclosure and an image' do
      let(:enclosure) { enclosure_for.call('episode.mp3', 'Audio/MPEG') }
      let(:image) { 'http://example.com/cover.jpg' }

      it 'renders only the <audio> player', :aggregate_failures do
        expect(doc.css('img, audio, video').map(&:name)).to eq(['audio'])
        expect(doc.at_css('audio source').to_h.slice('src', 'type'))
          .to eq('src' => 'http://example.com/episode.mp3', 'type' => 'Audio/MPEG')
      end
    end

    context 'with a document enclosure (no player) and an image' do
      let(:enclosure) { enclosure_for.call('report.pdf', 'application/pdf') }
      let(:image) { 'http://example.com/cover.jpg' }

      it 'renders the image instead of the document' do
        expect(doc.css('img, iframe').map { _1['src'] }).to eq(['http://example.com/cover.jpg'])
      end
    end

    context 'with an image enclosure and no item image' do
      let(:enclosure) { enclosure_for.call('photo.jpg', 'image/jpeg') }

      it 'renders no media' do
        expect(html).to eq('Caption')
      end
    end

    context 'when the description already shows the image' do
      {
        'a relative src' => ['hero,1.jpg', '<p><img src="/a/hero,1.jpg"> Caption</p>'],
        'a link to it' => ['hero,1.jpg', '<p><a href="HTTP://EXAMPLE.COM/a/hero,1.jpg">Caption</a></p>'],
        'a relative srcset candidate' => ['hero.jpg',
                                          '<img src="/a/s.jpg" srcset="s.jpg 1x, hero.jpg?x=1 2x,hero.jpg 3x">']
      }.each_pair do |reference, (file, markup)|
        it "renders no media element of its own with #{reference}" do
          image = Html2rss::Url.from_absolute("http://example.com/a/#{file}")
          html = described_class.new(base: markup, title: 'Harbor', url: 'http://example.com/a/post', enclosure:,
                                     image:)

          expect(Nokogiri::HTML.fragment(html.call).css('img[alt="Harbor"]')).to be_empty
        end
      end
    end

    context 'when the description does not contain the file name' do
      let(:image) { 'http://example.com/a/hero.jpg' }
      let(:base) { '<p><a href="http://example.com/a/">Section</a> img <img src="/a/other.jpg"></p>' }

      before { allow(Nokogiri::HTML).to receive(:fragment).and_call_original }

      it 'renders the image without parsing the description', :aggregate_failures do
        expect(doc.css('img').map { _1['src'] }).to eq(['http://example.com/a/hero.jpg', 'http://example.com/a/other.jpg'])
        expect(Nokogiri::HTML).to have_received(:fragment).once
      end
    end

    context 'with an empty description' do
      let(:image) { 'http://example.com/hero.jpg' }
      let(:base) { '' }

      it 'renders the image alone' do
        expect(html).to start_with('<img src="http://example.com/hero.jpg"').and end_with('>')
      end
    end

    context 'when the description only mentions the file name or links another URL with it' do
      let(:image) { 'http://example.com/a/hero.jpg' }
      let(:base) { '<p>See hero.jpg at <a href="/b/hero.jpg">b</a> or <img src="https://example.com/a/hero.jpg"></p>' }

      it 'still renders the image first' do
        expect(doc.css('img').map { _1['src'] }.first).to eq('http://example.com/a/hero.jpg')
      end
    end

    context 'when the description already embeds the audio file' do
      let(:enclosure) { enclosure_for.call('episode.mp3', 'audio/mpeg') }
      let(:image) { 'http://example.com/cover.jpg' }
      let(:base) { '<p><a href="/episode.mp3">Download</a></p>' }

      it 'renders no media at all' do
        expect(doc.css('img, audio, video')).to be_empty
      end
    end

    context 'when the file URL has no path segment' do
      let(:image) { 'http://example.com/' }
      let(:base) { '<a href="http://example.com">Home</a>' }

      it 'matches it by host' do
        expect(doc.css('img')).to be_empty
      end
    end

    context 'when the description holds an unparseable URL' do
      let(:image) { 'http://example.com/hero.jpg' }
      let(:base) { '<p>hero.jpg <img src="/x.jpg" srcset="http://a:b:c/ 1x"></p>' }

      it 'ignores it' do
        expect(doc.at_css('img')['src']).to eq('http://example.com/hero.jpg')
      end
    end
  end

  describe '.remove_pattern_from_start' do
    it 'removes the pattern when it is within the specified range' do
      original_text = 'Hello world! Start here.'
      pattern = 'world!'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq('Hello  Start here.')
    end

    it 'does not remove the pattern when it is outside the specified range' do
      original_text = 'This is a test. Remove this part.'
      pattern = 'part'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern, end_of_range: 10)
      expect(sanitized_text).to eq(original_text)
    end

    it 'returns the original text if the pattern is not found' do
      original_text = 'No match here.'
      pattern = 'missing'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq(original_text)
    end

    it 'returns the original text if the text is empty' do
      original_text = ''
      pattern = 'any'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq(original_text)
    end

    it 'removes pattern at the beginning of the text' do
      original_text = 'pattern should be removed from start'
      pattern = 'pattern'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq(' should be removed from start')
    end

    it 'handles pattern appearing multiple times in the text' do
      original_text = 'Repeat pattern and again pattern in text.'
      pattern = 'pattern'
      sanitized_text = described_class.remove_pattern_from_start(original_text, pattern)
      expect(sanitized_text).to eq('Repeat  and again pattern in text.')
    end

    {
      '<a href="HTTP://example.com/T">T: the harbor reopens today</a>' =>
        '<a href="HTTP://example.com/T">: the harbor reopens today</a>',
      '<b title="T.">T.</b> The harbor reopens today after a long winter' =>
        '<b title="T.">.</b> The harbor reopens today after a long winter',
      '5 < 6 T and the rest of a long enough sentence' => '5 < 6 T and the rest of a long enough sentence'
    }.each_pair do |text, expected|
      it "removes the pattern only from text content in #{text.inspect}" do
        expect(described_class.remove_pattern_from_start(text, 'T')).to eq(expected)
      end
    end

    it 'removes the pattern up to half the text by default', :aggregate_failures do
      expect(described_class.remove_pattern_from_start('abcTef', 'T')).to eq('abcef')
      expect(described_class.remove_pattern_from_start('abcdTf', 'T')).to eq('abcdTf')
    end

    it 'returns the text unchanged without a pattern' do
      expect(described_class.remove_pattern_from_start('Some text', nil)).to eq('Some text')
    end

    it 'removes a pattern written with regexp characters literally' do
      expect(described_class.remove_pattern_from_start('a.c (1) abc tail text', '(1)')).to eq('a.c  abc tail text')
    end
  end
end
