# frozen_string_literal: true

RSpec.describe Html2rss::Html::Rendering::MediaRenderer do
  describe '.for' do
    let(:enclosure_for) do
      ->(file, type) { Html2rss::Article::Enclosure.new(url: Html2rss::Url.from_absolute("https://example.com/#{file}"), type:) }
    end

    {
      ['a.mp3', 'Audio/MPEG'] => Html2rss::Html::Rendering::AudioRenderer,
      ['v.webm', 'VIDEO/WEBM; codecs=vp9'] => Html2rss::Html::Rendering::VideoRenderer,
      ['p.jpg', 'Image/JPEG'] => Html2rss::Html::Rendering::ImageRenderer,
      ['d.pdf', 'Application/PDF'] => Html2rss::Html::Rendering::PdfRenderer,
      ['s/1', nil] => NilClass,
      ['d.zip', nil] => NilClass
    }.each_pair do |(file, type), renderer|
      it "renders #{file} typed #{type.inspect} with #{renderer}" do
        expect(described_class.for(enclosure: enclosure_for.call(file, type), image: 'https://example.com/i.jpg',
                                   title: 'T')).to be_a(renderer)
      end
    end

    {
      ['a', 'Audio/MPEG'] => 'src="https://example.com/a" type="Audio/MPEG"',
      ['v', 'video/webm'] => 'src="https://example.com/v" type="video/webm"',
      ['d.pdf', nil] => 'src="https://example.com/d.pdf"',
      ['p.png', nil] => 'src="https://example.com/p.png"'
    }.each_pair do |(file, type), markup|
      it "passes the enclosure url and type of #{file} to its renderer" do
        html = described_class.for(enclosure: enclosure_for.call(file, type), image: nil, title: 'T').to_html

        expect(html).to include(markup)
      end
    end

    it 'passes the title to the image renderer' do
      html = described_class.for(enclosure: enclosure_for.call('p.jpg', nil), image: nil, title: 'Harbor').to_html

      expect(html).to include('alt="Harbor"')
    end

    it 'renders the fallback image without an enclosure, and nothing without either', :aggregate_failures do
      html = described_class.for(enclosure: nil, image: 'https://example.com/i.jpg', title: 'Harbor').to_html

      expect(html).to include('src="https://example.com/i.jpg"', 'alt="Harbor"')
      expect(described_class.for(enclosure: nil, image: nil, title: 'T')).to be_nil
    end
  end
end
