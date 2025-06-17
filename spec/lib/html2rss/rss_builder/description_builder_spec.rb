# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

RSpec.describe Html2rss::RssBuilder::DescriptionBuilder do
  subject(:description) { described_class.new(base:, title:, url:, enclosure:, image:).call }

  let(:title) { 'Sample instance' }
  let(:url) { 'http://example.com' }
  let(:image) { nil }
  let(:enclosure) { nil }

  def parse_html
    Nokogiri::HTML.fragment(description)
  end

  def expect_tag_with_attributes(tag, attributes)
    attributes.each do |key, value|
      if value.nil?
        expect(tag.has_attribute?(key)).to be true
      else
        expect(tag[key]).to eq(value)
      end
    end
  end

  describe '#call' do
    context 'when base description is present without HTML' do
      let(:base) { 'By John Doe' }

      it 'returns the base description unchanged' do
        expect(description).to eq('By John Doe')
      end
    end

    context 'when base description contains HTML' do
      let(:base) { '<b>Some bold text</b>' }

      before do
        allow(Html2rss::Selectors::PostProcessors::SanitizeHtml).to receive(:get)
          .with(base, url)
          .and_call_original
      end

      it 'sanitizes the HTML', :aggregate_failures do
        expect(description).to eq('<b>Some bold text</b>')
        expect(Html2rss::Selectors::PostProcessors::SanitizeHtml).to have_received(:get).with(base, url)
      end
    end

    context 'when description starts with the title' do
      let(:base) { 'Sample instance By John Doe' }

      it 'removes the title from the start' do
        expect(description).to include('By John Doe')
      end
    end

    context 'when image enclosure is present' do
      let(:base) { 'Caption' }
      let(:enclosure) do
        instance_double(Html2rss::RssBuilder::Enclosure,
                        url: 'http://example.com/image.jpg',
                        type: 'image/jpeg')
      end

      it 'renders correct <img> tag with attributes' do # rubocop:disable RSpec/ExampleLength
        img = parse_html.at_css('img')
        expect_tag_with_attributes(img, {
                                     'src' => 'http://example.com/image.jpg',
                                     'alt' => 'Sample instance',
                                     'title' => 'Sample instance',
                                     'loading' => 'lazy',
                                     'referrerpolicy' => 'no-referrer',
                                     'decoding' => 'async',
                                     'crossorigin' => 'anonymous'
                                   })
      end
    end

    context 'when fallback image is present' do
      let(:base) { 'Something' }
      let(:image) { 'http://example.com/fallback.jpg' }

      it 'renders fallback <img> tag with attributes' do # rubocop:disable RSpec/ExampleLength
        img = parse_html.at_css('img')
        expect(img).not_to be_nil
        expect_tag_with_attributes(img, {
                                     'src' => 'http://example.com/fallback.jpg',
                                     'alt' => 'Sample instance',
                                     'title' => 'Sample instance',
                                     'loading' => 'lazy',
                                     'referrerpolicy' => 'no-referrer',
                                     'decoding' => 'async',
                                     'crossorigin' => 'anonymous'
                                   })
      end
    end

    context 'when enclosure is a video' do
      let(:base) { 'Watch this' }
      let(:enclosure) do
        instance_double(Html2rss::RssBuilder::Enclosure,
                        url: 'http://example.com/video.mp4',
                        type: 'video/mp4')
      end

      it 'renders correct <video> and <source> tags with attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        doc = parse_html
        video = doc.at_css('video')
        source = video&.at_css('source')

        expect(video).not_to be_nil
        expect(source).not_to be_nil

        expect_tag_with_attributes(video, {
                                     'controls' => nil,
                                     'preload' => 'none',
                                     'referrerpolicy' => 'no-referrer',
                                     'crossorigin' => 'anonymous',
                                     'playsinline' => nil
                                   })

        expect_tag_with_attributes(source, {
                                     'src' => 'http://example.com/video.mp4',
                                     'type' => 'video/mp4'
                                   })
      end
    end

    context 'when enclosure is audio' do
      let(:base) { 'Listen to this' }
      let(:enclosure) do
        instance_double(Html2rss::RssBuilder::Enclosure,
                        url: 'http://example.com/audio.mp3',
                        type: 'audio/mpeg')
      end

      it 'renders correct <audio> and <source> tags with attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        doc = parse_html
        audio = doc.at_css('audio')
        source = audio&.at_css('source')

        expect(audio).not_to be_nil
        expect(source).not_to be_nil

        expect_tag_with_attributes(audio, {
                                     'controls' => nil,
                                     'preload' => 'none',
                                     'referrerpolicy' => 'no-referrer',
                                     'crossorigin' => 'anonymous'
                                   })

        expect_tag_with_attributes(source, {
                                     'src' => 'http://example.com/audio.mp3',
                                     'type' => 'audio/mpeg'
                                   })
      end
    end

    context 'when enclosure is a PDF' do
      let(:base) { 'See this document' }
      let(:enclosure) do
        instance_double(Html2rss::RssBuilder::Enclosure,
                        url: 'http://example.com/doc.pdf',
                        type: 'application/pdf')
      end

      it 'renders correct <iframe> tag with attributes' do # rubocop:disable RSpec/ExampleLength
        iframe = parse_html.at_css('iframe')
        expect(iframe).not_to be_nil

        expect_tag_with_attributes(iframe, {
                                     'src' => 'http://example.com/doc.pdf',
                                     'width' => '100%',
                                     'height' => '75vh',
                                     'sandbox' => '',
                                     'referrerpolicy' => 'no-referrer',
                                     'loading' => 'lazy'
                                   })
      end
    end

    context 'when everything is nil or empty' do
      let(:base) { '' }

      it 'returns nil' do
        expect(description).to be_nil
      end
    end
  end
end
