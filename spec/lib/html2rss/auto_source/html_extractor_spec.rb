# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::HtmlExtractor do
  subject(:article_hash) { described_class.new(article_tag, url: 'https://example.com').call }

  describe '.visible_text_from_tag' do
    subject(:visible_text) { described_class.visible_text_from_tag(tag) }

    let(:tag) do
      Nokogiri::HTML.fragment('<div>Hello <span>World</span><script>App = {}</script></div>').at_css('div')
    end

    it 'returns the visible text from the tag and its children' do
      expect(visible_text).to eq('Hello World')
    end
  end

  describe '.find_tag_in_ancestors' do
    let(:html) do
      <<-HTML
        <body>
          <article>
            <p>
              <a href="#" id="link">Link</a>
            </p>
          </article>
        </body>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }
    let(:current_tag) { document.at_css('#link') }

    context 'when the anchor is inside the specified tag' do
      it 'returns the specified tag' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'article')
        expect(article_tag.name).to eq('article')
      end
    end

    context 'when the anchor is not inside the specified tag' do
      it 'returns stop_tag' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'body')
        expect(article_tag).to be document.at_css('body')
      end
    end

    context 'when the anchor is the specified tag' do
      let(:html) do
        <<-HTML
          <article id="link">
            <p>Content</p>
          </article>
        HTML
      end

      it 'returns the anchor itself' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'article')
        expect(article_tag).to eq(current_tag)
      end
    end
  end

  describe '.find_closest_selector' do
    let(:html) do
      <<-HTML
      <body>
        <div id="container">
          <p>
            <a href="#" id="link">Link</a>
          </p>
        </div>
      </body>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }
    let(:container) { document.at_css('#container') }

    context 'when the anchor is directly within the element' do
      it 'returns the anchor' do
        anchor = described_class.find_closest_selector(container)
        expect(anchor['id']).to eq('link')
      end
    end

    context 'when the anchor is nested within the element' do
      let(:nested_html) do
        <<-HTML
        <body>
          <div id="container">
            <div>
              <a href="#" id="nested-link">Nested Link</a>
            </div>
          </div>
        </body>
        HTML
      end

      it 'returns the nested anchor' do
        nested_document = Nokogiri::HTML(nested_html)
        nested_container = nested_document.at_css('#container')

        anchor = described_class.find_closest_selector(nested_container)
        expect(anchor['id']).to eq('nested-link')
      end
    end

    context 'when there is no anchor within the element' do
      let(:no_anchor_container) do
        no_anchor_html = <<-HTML
        <body>
          <div id="container">
            <p>No link here</p>
          </div>
        </body>
        HTML

        Nokogiri::HTML(no_anchor_html).at_css('#container')
      end

      it 'returns nil' do
        anchor = described_class.find_closest_selector(no_anchor_container)
        expect(anchor).to be_nil
      end
    end
  end

  describe '.find_closest_selector_upwards' do
    let(:html) do
      <<-HTML
        <div>
          <p>
            <a href="#" id="link">Link</a>
            <span id="span">
              <p>:rocket:</p>
            </span>
          </p>
        </div>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }

    let(:expected_anchor) { document.at_css('a') }

    context 'when an anchor is sibling to current_tag' do
      let(:current_tag) { document.at_css('#span') }

      it 'returns the closest anchor in as sibling' do
        anchor = described_class.find_closest_selector_upwards(current_tag, 'a')
        expect(anchor).to eq(expected_anchor)
      end
    end

    context 'when an anchor is not below current_tag' do
      let(:current_tag) { document.at_css('p') }

      it 'returns the anchor upwards from current_tag' do
        anchor = described_class.find_closest_selector_upwards(current_tag, 'a')
        expect(anchor).to eq(expected_anchor)
      end
    end
  end

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
          <video> <source src="video.mp4" type="video/mp4"></video>
        </article>
      HTML
    end

    describe '#call' do
      let(:article_tag) { Nokogiri::HTML.fragment(html) }
      let(:heading) { article_tag.at_css('h1') }

      it 'returns the article_hash', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(article_hash).to a_hash_including(
          title: 'Sample Heading',
          description: 'Sample Heading FCK PTN Sample description',
          id: 'fck-ptn',
          published_at: an_instance_of(DateTime),
          url: an_instance_of(Addressable::URI),
          image: an_instance_of(Addressable::URI),
          enclosure: a_hash_including(
            url: an_instance_of(Addressable::URI),
            type: 'video/mp4'
          )
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
      let(:article_tag) { Nokogiri::HTML.fragment(html) }

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

    let(:article_tag) { Nokogiri::HTML.fragment(html) }

    it 'returns nil' do
      expect(article_hash).to be_nil
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
