# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

RSpec.describe Html2rss::Rendering::DescriptionBuilder do
  describe '#call' do
    context 'when base is plain text' do
      subject(:description) { described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures: nil, image: nil).call }

      let(:base) { 'By John Doe' }

      it 'returns the base description unchanged' do
        expect(description).to eq('By John Doe')
      end
    end

    context 'when base contains HTML' do
      subject(:description) do
        described_class.new(base:, title: 'Sample instance', url:, enclosures: nil, image: nil).call
      end

      let(:base) { '<b>Some bold text</b>' }
      let(:url) { 'http://example.com' }

      before do
        allow(Html2rss::Selectors::PostProcessors::SanitizeHtml).to receive(:get).with(base, url).and_call_original
      end

      it 'sanitizes the HTML', :aggregate_failures do
        expect(description).to eq('<b>Some bold text</b>')
        expect(Html2rss::Selectors::PostProcessors::SanitizeHtml).to have_received(:get).with(base, url)
      end
    end

    context 'when base starts with the title' do
      subject(:description) { described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures: nil, image: nil).call }

      let(:base) { 'Sample instance By John Doe' }

      it 'removes the title from the start' do
        expect(description).to include('By John Doe')
      end
    end

    context 'when base is empty' do
      subject(:description) { described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures: nil, image: nil).call }

      let(:base) { '' }

      it 'returns nil' do
        expect(description).to be_nil
      end
    end

    context 'when enclosure is an image' do
      subject(:doc) do
        html = described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures:,
                                   image: nil).call
        Nokogiri::HTML.fragment(html)
      end

      let(:base) { 'Caption' }
      let(:enclosures) { [instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/image.jpg', type: 'image/jpeg')] }

      it 'renders <img> with attributes', :aggregate_failures do
        img = doc.at_css('img')
        expect(img['src']).to eq('http://example.com/image.jpg')
        expect(img['alt']).to eq('Sample instance')
        expect(img['title']).to eq('Sample instance')
      end
    end

    context 'when fallback image is present (rendering)' do
      subject(:doc) do
        html = described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures: nil,
                                   image:).call
        Nokogiri::HTML.fragment(html)
      end

      let(:base) { 'Something' }
      let(:image) { 'http://example.com/fallback.jpg' }

      it 'renders fallback <img>' do
        img = doc.at_css('img')
        expect(img['src']).to eq('http://example.com/fallback.jpg')
      end
    end

    context 'when enclosure is a video' do
      subject(:doc) do
        html = described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures:,
                                   image: nil).call
        Nokogiri::HTML.fragment(html)
      end

      let(:base) { 'Watch this' }
      let(:enclosures) { [instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/video.mp4', type: 'video/mp4')] }

      it 'renders <video> and <source>', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        video = doc.at_css('video')
        source = video.at_css('source')
        expect(video).not_to be_nil
        expect(source).not_to be_nil
        expect(source['src']).to eq('http://example.com/video.mp4')
        expect(source['type']).to eq('video/mp4')
      end
    end

    context 'when enclosure is audio' do
      subject(:doc) do
        html = described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures:,
                                   image: nil).call
        Nokogiri::HTML.fragment(html)
      end

      let(:base) { 'Listen to this' }
      let(:enclosures) { [instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/audio.mp3', type: 'audio/mpeg')] }

      it 'renders <audio> and <source>', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        audio = doc.at_css('audio')
        source = audio.at_css('source')
        expect(audio).not_to be_nil
        expect(source).not_to be_nil
        expect(source['src']).to eq('http://example.com/audio.mp3')
        expect(source['type']).to eq('audio/mpeg')
      end
    end

    context 'when enclosure is a PDF' do
      subject(:doc) do
        html = described_class.new(base:, title: 'Sample instance', url: 'http://example.com', enclosures:,
                                   image: nil).call
        Nokogiri::HTML.fragment(html)
      end

      let(:base) { 'See this document' }
      let(:enclosures) { [instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/doc.pdf', type: 'application/pdf')] }

      it 'renders <iframe>', :aggregate_failures do
        iframe = doc.at_css('iframe')
        expect(iframe).not_to be_nil
        expect(iframe['src']).to eq('http://example.com/doc.pdf')
        expect(iframe['width']).to eq('100%')
        expect(iframe['height']).to eq('75vh')
      end
    end
  end
end
