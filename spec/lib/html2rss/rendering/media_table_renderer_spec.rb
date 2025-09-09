# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

RSpec.describe Html2rss::Rendering::MediaTableRenderer do
  describe '#to_html' do
    context 'when no media is available' do
      subject(:renderer) { described_class.new(enclosures: [], image: nil) }

      it 'returns nil' do
        expect(renderer.to_html).to be_nil
      end
    end

    context 'when only enclosures are present' do
      subject(:doc) { Nokogiri::HTML.fragment(html) }

      let(:html) { renderer.to_html }

      let(:renderer) do
        described_class.new(
          enclosures: [
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/image.jpg', type: 'image/jpeg'),
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/video.mp4', type: 'video/mp4'),
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/audio.mp3', type: 'audio/mpeg'),
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/doc.pdf', type: 'application/pdf')
          ],
          image: nil
        )
      end

      it 'renders a details element with summary', :aggregate_failures do
        details = doc.at_css('details')
        summary = details.at_css('summary')

        expect(details).not_to be_nil
        expect(summary).not_to be_nil
        expect(summary.text).to eq('Available resources')
      end

      it 'renders a table with proper headers', :aggregate_failures do
        table = doc.at_css('table')
        headers = table.css('th')

        expect(table).not_to be_nil
        expect(headers.map(&:text)).to eq(%w[Type URL Actions])
      end

      it 'renders all enclosure rows with proper content', :aggregate_failures do
        rows = doc.css('tbody tr')
        expect(rows.length).to eq(4)
        expect_all_enclosure_rows(rows)
      end

      it 'escapes URLs properly' do
        renderer = create_renderer_with_special_chars
        html = renderer.to_html
        expect_escaped_html(html)
      end
    end

    context 'when only fallback image is present' do
      subject(:doc) { Nokogiri::HTML.fragment(html) }

      let(:html) { renderer.to_html }

      let(:renderer) do
        described_class.new(
          enclosures: [],
          image: 'http://example.com/fallback.jpg'
        )
      end

      it 'renders a single image row', :aggregate_failures do
        rows = doc.css('tbody tr')
        expect(rows.length).to eq(1)
        expect_fallback_image_row(rows[0])
      end
    end

    context 'when both enclosures and fallback image are present' do
      subject(:doc) { Nokogiri::HTML.fragment(html) }

      let(:html) { renderer.to_html }

      let(:renderer) do
        described_class.new(
          enclosures: [
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/video.mp4', type: 'video/mp4')
          ],
          image: 'http://example.com/fallback.jpg'
        )
      end

      it 'renders both enclosure and fallback image rows', :aggregate_failures do
        rows = doc.css('tbody tr')
        expect(rows.length).to eq(2)
        expect_video_row(rows[0])
        expect_fallback_image_row(rows[1])
      end
    end

    context 'when fallback image duplicates an image enclosure' do
      subject(:doc) { Nokogiri::HTML.fragment(html) }

      let(:html) { renderer.to_html }

      let(:renderer) do
        described_class.new(
          enclosures: [
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/image.jpg', type: 'image/jpeg')
          ],
          image: 'http://example.com/image.jpg'
        )
      end

      it 'does not duplicate the image row', :aggregate_failures do
        rows = doc.css('tbody tr')

        expect(rows.length).to eq(1)
        expect(rows[0].at_css('td:first-child').text).to include('🖼️ Image')
      end
    end

    context 'with unknown file types' do
      subject(:doc) { Nokogiri::HTML.fragment(html) }

      let(:html) { renderer.to_html }

      let(:renderer) do
        described_class.new(
          enclosures: [
            instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/file.xyz',
                                                             type: 'application/unknown')
          ],
          image: nil
        )
      end

      it 'renders with generic file icon and label', :aggregate_failures do
        row = doc.at_css('tbody tr')

        expect(row.at_css('td:first-child').text).to include('📎 File')
        expect(row.at_css('td:last-child').text).to include('Download')
      end
    end
  end

  private

  def expect_image_row(row)
    expect(row.at_css('td:first-child').text).to include('🖼️ Image')
    expect(row.at_css('td:nth-child(2) a')['href']).to eq('http://example.com/image.jpg')
    expect(row.at_css('td:last-child').text).to include('View')
  end

  def expect_video_row(row)
    expect(row.at_css('td:first-child').text).to include('🎥 Video')
    expect(row.at_css('td:nth-child(2) a')['href']).to eq('http://example.com/video.mp4')
    expect(row.at_css('td:last-child').text).to include('Play')
  end

  def expect_audio_row(row)
    expect(row.at_css('td:first-child').text).to include('🎵 Audio')
    expect(row.at_css('td:nth-child(2) a')['href']).to eq('http://example.com/audio.mp3')
    expect(row.at_css('td:last-child').text).to include('Play')
  end

  def expect_pdf_row(row)
    expect(row.at_css('td:first-child').text).to include('📄 PDF Document')
    expect(row.at_css('td:nth-child(2) a')['href']).to eq('http://example.com/doc.pdf')
    expect(row.at_css('td:last-child').text).to include('Open')
  end

  def expect_fallback_image_row(row)
    expect(row.at_css('td:first-child').text).to include('🖼️ Image')
    expect(row.at_css('td:nth-child(2) a')['href']).to eq('http://example.com/fallback.jpg')
    expect(row.at_css('td:last-child').text).to include('View')
  end

  def expect_all_enclosure_rows(rows)
    expect_image_row(rows[0])
    expect_video_row(rows[1])
    expect_audio_row(rows[2])
    expect_pdf_row(rows[3])
  end

  def expect_escaped_html(html)
    expect(html).to include('http://example.com/file with spaces.jpg')
    expect(html).not_to include('<script>')
  end

  def create_renderer_with_special_chars
    described_class.new(
      enclosures: [
        instance_double(Html2rss::RssBuilder::Enclosure, url: 'http://example.com/file with spaces.jpg',
                                                         type: 'image/jpeg')
      ],
      image: nil
    )
  end
end
