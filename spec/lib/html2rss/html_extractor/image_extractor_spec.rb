# frozen_string_literal: true

require 'nokogiri'
require 'addressable'

RSpec.describe Html2rss::HtmlExtractor::ImageExtractor do
  let(:article_tag) { Nokogiri::HTML.fragment(html) }

  describe '.call' do
    subject(:url) { described_class.call(article_tag, base_url: 'https://example.com').to_s.encode('UTF-8') }

    let(:html) do
      <<~HTML
        <article>
          <img src="data:image/jpeg;base64,/9j/4AAQSkZJRgABAgAAZABkAAD" alt="Data Image" />
          <img src="image.jpg" alt="Image" />
        </article>
      HTML
    end

    context 'when image source is present in article tag' do
      it 'returns the absolute URL of the image source' do
        expect(url).to eq('https://example.com/image.jpg')
      end
    end

    context 'when image source is present and image url contains commas' do
      let(:html) do
        <<~HTML
          <article>
            <img srcset="image,with,commas.jpg 256w, another,image,with,commas.jpg 1w" alt="Image with commas" />
          </article>
        HTML
      end

      it 'returns the absolute URL of the image source' do
        expect(url).to eq('https://example.com/image,with,commas.jpg')
      end
    end

    context 'when image source is present in srcset attribute' do
      let(:html) do
        <<~HTML
          <article>
            <picture>
              <source srcset="
              https://example.com/wirtschaft/Deutschland-muss-sich-technologisch-weiterentwickeln-schnell.1200w.jpg 1200w,
              https://example.com/wirtschaft/Deutschland-muss-sich-technologisch-weiterentwickeln-schnell.200w.jpg 200w,
              https://example.com/wirtschaft/Deutschland-muss-sich-technologisch-weiterentwickeln-schnell.2000w.jpg 2000w" />
              <img src="https://example.com/wirtschaft/Deutschland-muss-sich-technologisch-weiterentwickeln-schnell.20w.jpg"
                 alt="Kein alternativer Text für dieses Bild vorhanden" loading="lazy" decoding="async" />
            </picture>
          </article>
        HTML
      end

      it 'returns the absolute URL of the "largest" image source' do
        expect(url).to eq('https://example.com/wirtschaft/Deutschland-muss-sich-technologisch-weiterentwickeln-schnell.2000w.jpg')
      end
    end

    context 'when [srcset] contains no spaces between sources' do
      let(:html) do
        <<~HTML
          <picture>
            <img srcset="https://example.com/image.88w.jpg 88w,https://example.com/image.175w.jpg 175w"/>
          </picture>
        HTML
      end

      it { is_expected.to eq('https://example.com/image.175w.jpg') }
    end

    context 'when image source is present in style attribute' do
      ['background-image: url("image.jpg");',
       'background: url(image.jpg);',
       "background: url('image.jpg');"].each do |style|
        let(:html) do
          <<~HTML
            <article>
              <div style="#{style}"></div>
            </article>
          HTML
        end

        it "returns the absolute URL from #{style}" do
          expect(url).to eq('https://example.com/image.jpg')
        end
      end
    end

    context 'when image source is not present' do
      let(:html) { '<article></article>' }

      it 'returns nil' do
        expect(described_class.call(article_tag, base_url: nil)).to be_nil
      end
    end
  end
end
