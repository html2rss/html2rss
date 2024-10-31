# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml::Extractor do
  subject(:article_hash) { described_class.new(article_tag, url:).call }

  let(:article_tag) { Nokogiri::HTML.fragment(html) }
  let(:url) { 'https://example.com' }

  context 'when heading is present' do
    let(:html) do
      <<~HTML
        <article id="fck-ptn">
          <h1>
            <a href="/sample">Sample Heading</a>
          </h1>
          <time datetime="2024-02-24T12:00-03:00">FCK PTN</time>
          <p>Sample description</p>
          <img src="image.jpg" alt="Image" />
        </article>
      HTML
    end

    describe '#call' do
      let(:heading) { article_tag.at_css('h1') }

      it 'returns the article_hash', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(article_hash).to a_hash_including(
          title: 'Sample Heading',
          description: 'Sample Heading FCK PTN Sample description',
          id: 'fck-ptn',
          published_at: an_instance_of(DateTime),
          url: an_instance_of(Addressable::URI),
          image: an_instance_of(Addressable::URI)
        )

        expect(article_hash[:published_at].to_s).to eq '2024-02-24T12:00:00-03:00'
        expect(article_hash[:url].to_s).to eq 'https://example.com/sample'
        expect(article_hash[:image].to_s).to eq 'https://example.com/image.jpg'
      end
    end

    context 'with invalid datetime' do
      let(:html) do
        <<~HTML
          <article id="fck-ptn">
            <h1>Sample Heading</h1>
            <time datetime="invalid">FCK PTN</time>
          </article>
        HTML
      end

      it 'returns the article_hash with a nil published_at' do
        expect(article_hash[:published_at]).to be_nil
      end
    end
  end

  context 'when heading is not present' do
    let(:html) do
      <<~HTML
        <article>
          <time datetime="2024-02-24 12:00">FCK PTN</time>
          <p>Sample description</p>
          <img src="image.jpg" alt="Image" />
        </article>
      HTML
    end

    it 'returns nil' do
      expect(article_hash).to be_nil
    end
  end

  describe '.visible_text_from_tag' do
    subject(:visible_text) { described_class.visible_text_from_tag(tag) }

    let(:tag) do
      Nokogiri::HTML.fragment('<div>Hello <span>World</span><script>App = {}</script></div>').at_css('div')
    end

    it 'returns the visible text from the tag and its children' do
      expect(visible_text).to eq('Hello World')
    end
  end

  describe '#find_heading' do
    subject(:find_heading) { described_class.new(article_tag, url: 'https://example.com').send(:find_heading) }

    let(:article_tag) { Nokogiri::HTML.fragment(html) }

    context 'when heading is present' do
      let(:html) do
        <<~HTML
          <article>
            <h1>Heading 1</h1>
            <h2>Heading 2</h2>
            <h3>Heading 3</h3>
          </article>
        HTML
      end

      it 'returns the smallest heading with the largest visible text', :aggregate_failures do
        expect(find_heading.name).to eq('h1')
        expect(find_heading.text).to eq('Heading 1')
      end
    end

    context 'when heading is not present' do
      let(:html) do
        <<~HTML
          <article>
            <p>Paragraph 1</p>
            <p>Paragraph 2</p>
          </article>
        HTML
      end

      it 'returns nil' do
        expect(find_heading).to be_nil
      end
    end
  end
end
