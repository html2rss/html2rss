# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::ArticleExtractor do
  subject(:article_hash) { described_class.call(article_tag, base_url: 'https://example.com', selected_anchor:) }

  let(:selected_anchor) { Html2rss::Html::Navigator.main_anchor_for(article_tag) }

  describe '#call with selected_anchor' do
    let(:article_tag) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('article')
        <article id="story">
          <a href="/category/news">News</a>
          <h2><a href="/article/42">Correct Story</a></h2>
          <p>Summary text</p>
        </article>
      HTML
    end
    let(:selected_anchor) { article_tag.at_css('h2 a') }

    it 'uses the provided anchor for url extraction', :aggregate_failures do
      expect(article_hash[:url].to_s).to eq('https://example.com/article/42')
      expect(article_hash[:title]).to eq('Correct Story')
      expect(article_hash[:id]).to eq('story')
    end
  end

  context 'when heading is present' do
    let(:html) do
      <<~HTML
        <article id="fck-ptn">
          <a href="#">Scroll to top</a>
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
          description: "FCK PTN\nSample description",
          id: 'fck-ptn',
          published_at: an_instance_of(DateTime),
          url: Html2rss::Url.from_absolute('https://example.com/sample'),
          image: be_a(Html2rss::Url),
          categories: [],
          enclosures: contain_exactly(a_hash_including(
                                        url: be_a(Html2rss::Url),
                                        type: 'video/mp4'
                                      ), a_hash_including(
                                           url: be_a(Html2rss::Url),
                                           type: 'image/jpeg'
                                         ))
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
    let(:details) do
      { title: nil,
        url: nil,
        image: be_a(Html2rss::Url),
        description: "FCK PTN\nSample description",
        id: nil,
        published_at: be_a(DateTime),
        categories: [],
        enclosures: [a_hash_including(
          url: be_a(Html2rss::Url),
          type: 'image/jpeg'
        )] }
    end

    it 'returns the details' do
      expect(article_hash).to match(details)
    end
  end

  # Heading selection intent via public #call title (AGENTS forbids send in specs).
  context 'when choosing among multiple headings' do
    let(:html) do
      <<~HTML
        <article>
          <h1>Heading 1</h1>
          <h2>Heading 2</h2>
          <h3>Heading 3</h3>
        </article>
      HTML
    end
    let(:article_tag) { Nokogiri::HTML.fragment(html) }

    it 'uses the smallest heading with the largest visible text as the title' do
      expect(article_hash[:title]).to eq('Heading 1')
    end
  end

  describe 'kicker extraction' do
    let(:html) do
      <<~HTML
        <article>
          <span class="teaser-kicker">Kicker Text</span>
          <h3>Headline Text</h3>
          <p>Description Text</p>
        </article>
      HTML
    end
    let(:article_tag) { Nokogiri::HTML.fragment(html) }

    it 'prepends kicker to title and excludes it from description', :aggregate_failures do
      expect(article_hash[:title]).to eq('Kicker Text: Headline Text')
      expect(article_hash[:description]).to eq('Description Text')
    end
  end

  context 'when fallback_anchorless is true and selected_anchor is nil' do
    subject(:article_hash) do
      described_class.call(
        article_tag,
        base_url: 'https://example.com',
        selected_anchor: nil,
        fallback_anchorless: true
      )
    end

    context 'with strong fallback heading' do
      let(:html) do
        <<~HTML
          <article>
            <strong class="title">Fallback Article Title</strong>
            <p>Some content description here.</p>
          </article>
        HTML
      end
      let(:article_tag) { Nokogiri::HTML.fragment(html) }

      it 'extracts the fallback title, url and id', :aggregate_failures do
        expect(article_hash[:title]).to eq('Fallback Article Title')
        expect(article_hash[:id]).to eq('fallback-article-title')
        expect(article_hash[:url].to_s).to eq('https://example.com/#fallback-article-title')
      end
    end

    context 'with no heading tags but has visible text' do
      let(:html) do
        <<~HTML
          <article>
            Some plain text description.
          </article>
        HTML
      end
      let(:article_tag) { Nokogiri::HTML.fragment(html) }

      it 'falls back to text node content for title/id extraction', :aggregate_failures do
        expect(article_hash[:title]).to eq('Some plain text description.')
        expect(article_hash[:id]).to eq('some-plain-text-description')
        expect(article_hash[:url].to_s).to eq('https://example.com/#some-plain-text-description')
      end
    end

    context 'when article_tag is a text node' do
      let(:article_tag) { Nokogiri::HTML.fragment('hello').children.first }

      it 'falls back to generating a content hash ID', :aggregate_failures do
        expect(article_hash[:title]).to be_nil
        expect(article_hash[:id]).to eq('f01gna')
        expect(article_hash[:url].to_s).to eq('https://example.com/#f01gna')
      end
    end
  end
end
