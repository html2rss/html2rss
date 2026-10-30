# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::ArticleExtractor do
  subject(:article_hash) do
    described_class.call(article_tag, base_url: 'https://example.com', selected_anchor:, time_zone: 'UTC')
  end

  let(:selected_anchor) { Html2rss::Html::Navigator.main_anchor_for(article_tag) }

  describe 'leftover hygiene' do
    let(:extractor_time_zone) { 'UTC' }
    let(:leftover_fields) do
      lambda do |html, item_selector: 'article'|
        tag = Nokogiri::HTML.fragment(html).at_css(item_selector)
        described_class.call(
          tag,
          base_url: 'https://example.com',
          selected_anchor: Html2rss::Html::Navigator.main_anchor_for(tag),
          time_zone: extractor_time_zone
        )
      end
    end

    it_behaves_like 'article extractor leftover hygiene'
  end

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
          description: 'Sample description',
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
        description: 'Sample description',
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

  # Scenario groups below are shared into each per-method describe so that
  # expression-scoped mutation runs see behaviour for the method under test.
  shared_examples 'extractor defaults' do
    let(:article_tag) do
      Nokogiri::HTML.fragment('<article><time datetime="2024-02-24 12:00">Feb 24</time><p>Body text</p></article>')
                    .at_css('article')
    end

    it 'uses no anchor, no anchorless fallback and UTC by default', :aggregate_failures do
      extracted = described_class.call(article_tag, base_url: 'https://example.com')
      expect(extracted[:url]).to be_nil
      expect(extracted[:title]).to be_nil
      expect(extracted[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
      expect(extracted[:description]).to eq('Body text')
    end
  end

  shared_examples 'card walk from heading item' do
    let(:card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <h3><a href="/story/1">Card Title</a></h3>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end
    let(:item) { card.at_css('h3') }

    it 'takes the summary and date from the parent card', :aggregate_failures do
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to eq('Card summary text')
      expect(extracted[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end
  end

  shared_examples 'crowded parent card' do
    let(:crowded) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <h3><a href="/story/1">Card Title</a></h3>
          <h3><a href="/story/2">Other Title</a></h3>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'does not take the summary from a parent holding several headings', :aggregate_failures do
      item = crowded.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to be_nil
      expect(extracted[:published_at]).to be_nil
    end
  end

  shared_examples 'thin wrapper card' do
    let(:thin_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <div class="inner"><h3><a href="/story/1">Card Title</a></h3></div>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'walks past a wrapper whose only child is the heading', :aggregate_failures do
      item = thin_card.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to eq('Card summary text')
      expect(extracted[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end
  end

  shared_examples 'nested thin wrapper card' do
    let(:nested_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <div class="inner"><div class="wrap"><h3><a href="/story/1">Card Title</a></h3></div></div>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'walks past wrappers that contain the heading item', :aggregate_failures do
      item = nested_card.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to eq('Card summary text')
    end
  end

  shared_examples 'plain item does not walk' do
    let(:plain_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <div class="item"><img src="x.jpg"></div>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'keeps the container item without walking to the parent card', :aggregate_failures do
      extracted = described_class.call(plain_card.at_css('.item'), base_url: 'https://example.com')
      expect(extracted[:published_at]).to be_nil
      expect(extracted[:description]).to be_nil
    end
  end

  shared_examples 'anchor item walks to parent card' do
    let(:anchor_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <a href="/story/1"><img src="x.jpg"></a>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'walks from a bare anchor item to the parent card', :aggregate_failures do
      anchor = anchor_card.at_css('a')
      extracted = described_class.call(anchor, base_url: 'https://example.com', selected_anchor: anchor)
      expect(extracted[:description]).to eq('Card summary text')
      expect(extracted[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end
  end

  shared_examples 'heading item with its own date' do
    let(:dated_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <h3><a href="/story/1">Card Title</a><time datetime="2024-02-24T12:00:00+00:00">Feb 24</time></h3>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'does not walk when the item already carries a date', :aggregate_failures do
      item = dated_card.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to be_nil
      expect(extracted[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end
  end

  shared_examples 'anchor href resolution' do
    let(:href_tag) do
      Nokogiri::HTML.fragment('<article><a href=" /article/42 #comments ">Story</a></article>').at_css('article')
    end

    it 'strips the fragment and surrounding whitespace from the selected anchor href' do
      extracted = described_class.call(href_tag, base_url: 'https://example.com', selected_anchor: href_tag.at_css('a'))
      expect(extracted[:url].to_s).to eq('https://example.com/article/42')
    end
  end

  shared_examples 'anchorless url resolution' do
    let(:anchorless_tag) { Nokogiri::HTML.fragment('<article><h2>Anchorless Story</h2></article>').at_css('article') }

    it 'returns no url without the anchorless fallback' do
      expect(described_class.call(anchorless_tag, base_url: 'https://example.com')[:url]).to be_nil
    end

    it 'links to the generated id with the anchorless fallback' do
      extracted = described_class.call(anchorless_tag, base_url: 'https://example.com', fallback_anchorless: true)
      expect(extracted[:url].to_s).to eq('https://example.com/#anchorless-story')
    end

    it 'returns no url when no id can be generated' do
      empty_tag = Nokogiri::HTML.fragment('<article><img src="x.jpg"></article>').at_css('article')
      expect(described_class.call(empty_tag, base_url: 'https://example.com',
                                             fallback_anchorless: true)[:url]).to be_nil
    end
  end

  shared_examples 'rich article attributes' do
    let(:rich_tag) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('article')
        <article id="rich">
          <h2><a href="/news/7">Rich Story</a></h2>
          <p>Rich description text</p>
          <img src="/pics/rich.jpg" alt="Rich">
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
        </article>
      HTML
    end

    it 'returns every attribute with resolved values', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      extracted = described_class.call(rich_tag, base_url: 'https://example.com',
                                                 selected_anchor: rich_tag.at_css('h2 a'))
      expect(extracted.keys).to contain_exactly(:title, :url, :image, :description, :id, :published_at, :enclosures,
                                                :categories)
      expect(extracted[:title]).to eq('Rich Story')
      expect(extracted[:url].to_s).to eq('https://example.com/news/7')
      expect(extracted[:image].to_s).to eq('https://example.com/pics/rich.jpg')
      expect(extracted[:description]).to eq('Rich description text')
      expect(extracted[:id]).to eq('rich')
      expect(extracted[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
      expect(extracted[:enclosures].map { |enclosure| enclosure[:url].to_s }).to eq(['https://example.com/pics/rich.jpg'])
      expect(extracted[:categories]).to eq([])
    end
  end

  shared_examples 'kicker title' do
    it 'returns nil when there is no heading, anchor or fallback text' do
      article_tag = Nokogiri::HTML.fragment('<article><span class="kicker">News</span></article>').at_css('article')
      expect(described_class.call(article_tag, base_url: 'https://example.com')[:title]).to be_nil
    end

    it 'returns the headline unchanged when there is no kicker' do
      article_tag = Nokogiri::HTML.fragment('<article><h3>Headline Text</h3></article>').at_css('article')
      expect(described_class.call(article_tag, base_url: 'https://example.com')[:title]).to eq('Headline Text')
    end

    it 'prefixes a trimmed kicker when the headline does not already contain it' do # rubocop:disable RSpec/ExampleLength
      article_tag = Nokogiri::HTML.fragment(
        '<article><span class="teaser-kicker">   Politics </span><h3>Headline Text</h3></article>'
      )
                                  .at_css('article')
      expect(described_class.call(article_tag,
                                  base_url: 'https://example.com')[:title]).to eq('Politics: Headline Text')
    end

    it 'does not prefix a kicker that the headline already contains' do
      article_tag = Nokogiri::HTML.fragment(
        '<article><span class="kicker">News</span><h3>News roundup today</h3></article>'
      )
                                  .at_css('article')
      expect(described_class.call(article_tag, base_url: 'https://example.com')[:title]).to eq('News roundup today')
    end
  end

  shared_examples 'selected anchor excluded from description' do
    let(:read_more_tag) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('article')
        <article>
          <h2>Headline</h2>
          <p>Body text</p>
          <a href="/story/9">Read more</a>
        </article>
      HTML
    end

    it 'excludes the selected anchor text from the description' do
      extracted = described_class.call(read_more_tag, base_url: 'https://example.com',
                                                      selected_anchor: read_more_tag.at_css('a'))
      expect(extracted[:description]).to eq('Body text')
    end
  end

  shared_examples 'crowded parent without links' do
    let(:bare_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <h3><a href="/story/1">Card Title</a></h3>
          <h3><a href="/story/1">Other Title</a></h3>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'does not walk to a parent holding several headings even when they share one link', :aggregate_failures do
      item = bare_card.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to be_nil
      expect(extracted[:published_at]).to be_nil
    end
  end

  shared_examples 'anchor href fragment' do
    let(:fragment_tag) do
      Nokogiri::HTML.fragment('<article><a href="/article/42#comments">Story</a></article>')
                    .at_css('article')
    end

    it 'drops the fragment from the selected anchor href' do
      extracted = described_class.call(fragment_tag, base_url: 'https://example.com',
                                                     selected_anchor: fragment_tag.at_css('a'))
      expect(extracted[:url].to_s).to eq('https://example.com/article/42')
    end
  end

  shared_examples 'fallback span title' do
    let(:span_tag) { Nokogiri::HTML.fragment('<article><span>Alpha</span> Beta</article>').at_css('article') }

    it 'uses the first visible text node as the fallback title' do
      extracted = described_class.call(span_tag, base_url: 'https://example.com', fallback_anchorless: true)
      expect(extracted[:title]).to eq('Alpha')
    end

    it 'derives no fallback title from an article without text' do
      empty_tag = Nokogiri::HTML.fragment('<article><img src="x.jpg"></article>').at_css('article')
      expect(described_class.call(empty_tag, base_url: 'https://example.com',
                                             fallback_anchorless: true)[:title]).to be_nil
    end
  end

  shared_examples 'anchor-only title' do
    let(:anchor_only_tag) do
      Nokogiri::HTML.fragment('<article><a href="/story/1">Anchor Story</a><p>Body text</p></article>')
                    .at_css('article')
    end

    it 'uses the selected anchor text as the title when there is no heading' do
      extracted = described_class.call(anchor_only_tag, base_url: 'https://example.com',
                                                        selected_anchor: anchor_only_tag.at_css('a'))
      expect(extracted[:title]).to eq('Anchor Story')
    end
  end

  shared_examples 'inline anchor excluded from description' do
    let(:inline_tag) do
      Nokogiri::HTML.fragment(
        '<article><h2>Headline</h2><p>Body <a href="/story/3">Story about cats</a> text</p></article>'
      )
                    .at_css('article')
    end

    it 'excludes the selected inline anchor text from the description' do
      extracted = described_class.call(inline_tag, base_url: 'https://example.com',
                                                   selected_anchor: inline_tag.at_css('a'))
      expect(extracted[:description]).to eq('Body text')
    end
  end

  shared_examples 'title line excluded from description' do
    let(:title_line_tag) do
      Nokogiri::HTML.fragment(
        '<article><h2><a href="/news/7">Rich Story</a></h2><p>Rich Story</p><p>Rich description text</p></article>'
      )
                    .at_css('article')
    end

    it 'drops a body line that repeats the title' do
      extracted = described_class.call(title_line_tag, base_url: 'https://example.com',
                                                       selected_anchor: title_line_tag.at_css('a'))
      expect(extracted[:description]).to eq('Rich description text')
    end
  end

  shared_examples 'categories from parent card' do
    let(:category_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <h3><a href="/story/1">Card Title</a></h3>
          <span class="category">Politics</span>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'takes categories from the parent card after walking to it' do
      item = category_card.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:categories]).to include('Politics')
    end
  end

  shared_examples 'categories from article' do
    it 'takes categories from the article when no walk happens' do
      article = Nokogiri::HTML.fragment(
        '<article><h3>Headline</h3><span class="category">Politics</span><p>Body</p></article>'
      )
                              .at_css('article')
      expect(described_class.call(article, base_url: 'https://example.com')[:categories]).to include('Politics')
    end
  end

  shared_examples 'landmark wrapper card' do
    let(:landmark_card) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <aside><h3><a href="/story/1">Card Title</a></h3></aside>
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
          <p>Card summary text</p>
        </div>
      HTML
    end

    it 'walks past a landmark wrapper to the parent card' do
      item = landmark_card.at_css('h3')
      extracted = described_class.call(item, base_url: 'https://example.com', selected_anchor: item.at_css('a'))
      expect(extracted[:description]).to eq('Card summary text')
    end
  end

  describe '.call' do
    it_behaves_like 'extractor defaults'
  end

  describe '#initialize' do
    let(:article_tag) { Nokogiri::HTML.fragment('<article><p>Body text</p></article>').at_css('article') }

    it 'requires an article tag' do
      expect { described_class.new(nil, base_url: 'https://example.com') }
        .to raise_error(ArgumentError, 'article_tag is required')
    end

    it 'resolves urls against the base url and selected anchor it was given' do
      tag = Nokogiri::HTML.fragment('<article><h2><a href="/news/7">Story</a></h2></article>').at_css('article')
      extracted = described_class.new(tag, base_url: 'https://example.com', selected_anchor: tag.at_css('a')).call
      expect(extracted[:url].to_s).to eq('https://example.com/news/7')
    end

    it 'builds with the optional arguments defaulted', :aggregate_failures do
      extracted = described_class.new(article_tag, base_url: 'https://example.com').call
      expect(extracted[:url]).to be_nil
      expect(extracted[:description]).to eq('Body text')
    end

    it_behaves_like 'extractor defaults'
  end

  describe '#call' do
    it_behaves_like 'rich article attributes'
    it_behaves_like 'inline anchor excluded from description'
    it_behaves_like 'title line excluded from description'
    it_behaves_like 'card walk from heading item'
    it_behaves_like 'selected anchor excluded from description'
  end

  describe '#extract_url' do
    it_behaves_like 'anchor href resolution'
    it_behaves_like 'anchor href fragment'
    it_behaves_like 'anchorless url resolution'
  end

  describe '#anchorless_url_fallback' do
    it_behaves_like 'anchorless url resolution'
  end

  describe '#generate_id' do
    it 'derives the id from the heading slug when the DOM has no id' do
      article_tag = Nokogiri::HTML.fragment('<article><h2>Plain Heading</h2></article>').at_css('article')
      expect(described_class.call(article_tag, base_url: 'https://example.com')[:id]).to eq('plain-heading')
    end

    it 'uses the selected anchor path as id when the article has no id' do
      article_tag = Nokogiri::HTML.fragment('<article><h2><a href="/article/42">Correct Story</a></h2></article>')
                                  .at_css('article')
      extracted = described_class.call(article_tag, base_url: 'https://example.com',
                                                    selected_anchor: article_tag.at_css('a'))
      expect(extracted[:id]).to eq('/article/42')
    end

    it 'falls back to the first visible text when anchorless fallback is enabled' do
      article_tag = Nokogiri::HTML.fragment("<article>\n  Some plain text description.\n</article>").at_css('article')
      extracted = described_class.call(article_tag, base_url: 'https://example.com', fallback_anchorless: true)
      expect(extracted[:id]).to eq('some-plain-text-description')
    end
  end

  describe '#extract_title' do
    it_behaves_like 'kicker title'
    it_behaves_like 'anchor-only title'
    it_behaves_like 'fallback span title'
  end

  describe '#fallback_anchorless_title' do
    let(:article_tag) do
      Nokogiri::HTML.fragment("<article>\n  <span></span>Plain fallback words\n</article>")
                    .at_css('article')
    end

    it_behaves_like 'fallback span title'

    it 'uses the first non-blank text node when the anchorless fallback is enabled' do
      extracted = described_class.call(article_tag, base_url: 'https://example.com', fallback_anchorless: true)
      expect(extracted[:title]).to eq('Plain fallback words')
    end

    it 'does not derive a title from text without the anchorless fallback' do
      expect(described_class.call(article_tag, base_url: 'https://example.com')[:title]).to be_nil
    end
  end

  describe '#heading' do
    it 'uses the anchorless fallback heading when enabled' do # rubocop:disable RSpec/ExampleLength
      tag = Nokogiri::HTML.fragment(
        '<article><strong class="title">Fallback Article Title</strong><p>Some body text.</p></article>'
      )
                          .at_css('article')
      expect(described_class.call(tag, base_url: 'https://example.com', fallback_anchorless: true)[:title])
        .to eq('Fallback Article Title')
    end
  end

  describe '#leftover_exclude_nodes_for' do
    it_behaves_like 'selected anchor excluded from description'
    it_behaves_like 'inline anchor excluded from description'
  end

  describe '#heading_or_anchor_item?' do
    it_behaves_like 'plain item does not walk'
    it_behaves_like 'anchor item walks to parent card'
    it_behaves_like 'card walk from heading item'
  end

  describe '#heading_or_anchor_miss?' do
    it_behaves_like 'heading item with its own date'
    it_behaves_like 'card walk from heading item'
    it_behaves_like 'plain item does not walk'
  end

  describe '#parent_card_fields' do
    it 'stops the walk without raising when the heading item has no parent', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      messages = []
      allow(Html2rss::Log).to receive(:debug) { |&block| messages << block.call }
      item = Nokogiri::HTML('<html><body></body></html>').create_element('h3')
      extracted = described_class.call(item, base_url: 'https://example.com')
      expect(extracted[:published_at]).to be_nil
      expect(messages).to include('parent-walk abort at ')
    end

    it_behaves_like 'card walk from heading item'
    it_behaves_like 'crowded parent without links'
    it_behaves_like 'categories from parent card'
    it_behaves_like 'categories from article'
    it_behaves_like 'crowded parent card'
    it_behaves_like 'thin wrapper card'
    it_behaves_like 'plain item does not walk'
    it_behaves_like 'anchor item walks to parent card'
    it_behaves_like 'heading item with its own date'

    it 'logs the aborted parent walk when the parent is crowded' do # rubocop:disable RSpec/ExampleLength
      messages = []
      allow(Html2rss::Log).to receive(:debug) { |&block| messages << block.call }
      crowded = Nokogiri::HTML.fragment(<<~HTML).at_css('.card')
        <div class="card">
          <h3><a href="/story/1">Card Title</a></h3>
          <h3><a href="/story/2">Other Title</a></h3>
          <p>Card summary text</p>
        </div>
      HTML
      described_class.call(crowded.at_css('h3'), base_url: 'https://example.com', selected_anchor: crowded.at_css('a'))
      expect(messages).to include('parent-walk abort at div')
    end
  end

  describe '#crowded_parent?' do
    it_behaves_like 'crowded parent card'
    it_behaves_like 'crowded parent without links'
    it_behaves_like 'card walk from heading item'
  end

  describe '#thin_heading_wrapper?' do
    it_behaves_like 'thin wrapper card'
    it_behaves_like 'nested thin wrapper card'
  end

  describe '#usable_walk_parent?' do
    it_behaves_like 'thin wrapper card'
    it_behaves_like 'landmark wrapper card'
  end

  describe '#extract_enclosures' do
    it 'resolves enclosure urls against the base url' do
      article_tag = Nokogiri::HTML.fragment('<article><img src="/pics/rich.jpg" alt="Rich"></article>')
                                  .at_css('article')
      extracted = described_class.call(article_tag, base_url: 'https://example.com')
      expect(extracted[:enclosures].map { |enclosure| enclosure[:url].to_s })
        .to eq(['https://example.com/pics/rich.jpg'])
    end
  end
end
