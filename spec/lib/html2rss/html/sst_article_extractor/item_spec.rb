# frozen_string_literal: true

RSpec.describe Html2rss::Html::SstArticleExtractor::Item do
  describe 'leftover hygiene' do
    let(:extractor_time_zone) { 'UTC' }
    let(:leftover_fields) do
      lambda do |html, item_selector: 'article'|
        item_fields_for(html, item: item_selector, time_zone: extractor_time_zone)
          .slice(:title, :description, :published_at, :categories, :url)
      end
    end

    it_behaves_like 'article extractor leftover hygiene'
  end

  describe 'kicker and headline pieces' do
    let(:title_for) { ->(html) { item_fields_for(html)[:title] } }

    it_behaves_like 'article extractor title pieces'
  end

  describe '#call' do
    it 'returns every attribute with resolved values', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fields = item_fields_for(<<~HTML)
        <article id="rich">
          <h2><a href="/news/7">Rich Story</a></h2>
          <p>Rich description text</p>
          <img src="/pics/rich.jpg" alt="Rich">
          <time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>
        </article>
      HTML

      expect(fields.keys).to contain_exactly(:title, :url, :image, :description, :id, :published_at, :enclosures,
                                             :categories)
      expect(fields.values_at(:title, :description, :id, :categories))
        .to eq(['Rich Story', 'Rich description text', 'rich', []])
      expect([fields[:url], fields[:image], fields[:published_at]].map(&:to_s))
        .to eq(['https://example.com/news/7', 'https://example.com/pics/rich.jpg', '2024-02-24T12:00:00+00:00'])
      expect(fields[:enclosures].map { _1[:url].to_s }).to eq(['https://example.com/pics/rich.jpg'])
    end

    it 'reads an item with a heading, a date, an image and a video', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fields = item_fields_for(<<~HTML)
        <article id="fck-ptn">
          <a href="#">Scroll to top</a>
          <h1><a href="/sample">Sample Heading</a></h1>
          <time datetime="2024-02-24T12:00-03:00">FCK PTN</time>
          <p>Sample description</p>
          <img src="image.jpg" alt="Image" />
          <video> <source src="video.mp4" type="video/mp4"></video>
        </article>
      HTML

      expect(fields.values_at(:title, :description, :id, :categories)).to eq(['Sample Heading', 'Sample description',
                                                                              'fck-ptn', []])
      expect([fields[:url], fields[:image], fields[:published_at]].map(&:to_s))
        .to eq(['https://example.com/sample', 'https://example.com/image.jpg', '2024-02-24T12:00:00-03:00'])
      expect(fields[:enclosures].map { _1[:type] }).to contain_exactly('video/mp4', 'image/jpeg')
    end

    it 'reads a card without a heading, a link or an id', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fields = item_fields_for(<<~HTML)
        <article>
          <time datetime="2024-02-24 12:00">FCK PTN</time>
          <p>Sample description</p>
          <img src="image.jpg" alt="Image" />
        </article>
      HTML

      expect(fields.values_at(:title, :url, :description, :id,
                              :categories)).to eq(['FCK PTN', nil, 'Sample description',
                                                   'fck-ptn', []])
      expect(fields[:published_at]).to be_a(DateTime)
    end

    it 'leaves the date empty for an invalid datetime' do
      expect(item_fields_for('<article><h1>Sample</h1><time datetime="invalid">x</time></article>')[:published_at])
        .to be_nil
    end

    it 'uses no link and UTC by default', :aggregate_failures do
      fields = item_fields_for('<article><time datetime="2024-02-24 12:00">Feb 24</time><p>Body text</p></article>')

      expect(fields.values_at(:url, :title, :description)).to eq([nil, 'Feb 24', 'Body text'])
      expect(fields[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end

    it 'resolves relative links against the base url given' do
      fields = item_fields_for('<article><h2><a href="/news/7">Story</a></h2></article>',
                               base_url: 'https://other.example/')

      expect(fields[:url].to_s).to eq('https://other.example/news/7')
    end

    it 'builds no article and drops nothing: a card without a url or text still yields its fields',
       :aggregate_failures do
      fields = item_fields_for('<article></article>')

      expect(fields).to include(title: nil, url: nil, description: nil, id: nil, categories: [], enclosures: [])
    end
  end

  describe 'title' do
    {
      'the smallest heading tag' => ['<div class="card"><h3>Tertiary</h3><h2>Secondary</h2><h1>Primary</h1></div>',
                                     'Primary'],
      'the longest text among equal headings' =>
        ['<div class="card"><h2>Short</h2><h2>The longer heading text</h2><h3>Lower</h3></div>',
         'The longer heading text'],
      'the longest text, not the first, among equal headings' =>
        ['<div class="card"><h2>A considerably longer heading first</h2><h2>Short</h2></div>',
         'A considerably longer heading first'],
      'a heading below the item, never the item itself' =>
        ['<div class="card"><h2>Inner</h2></div>', 'Inner'],
      'the first aria-label node when there is no heading tag' =>
        ['<div class="card"><a href="/x">First</a><a href="/s" aria-label="Breaking story">Second</a></div>',
         'Second'],
      'the first title attribute node after blank aria-labels' =>
        ['<div class="card"><a href="/x">First</a><a href="/s" aria-label="" title="Title wins">Second</a></div>',
         'Second'],
      'aria-label before title, skipping blank ones' =>
        ['<div class="card"><a href="/s" aria-label="  " title="Real">icon</a><a aria-label="Labelled">other</a></div>',
         'other'],
      'the selected anchor without a heading or label' =>
        ['<article><a href="/story/1">Anchor Story</a><p>Body text</p></article>', 'Anchor Story'],
      'the first non-blank text node of an item without heading or anchor' =>
        ["<article>\n  <span></span>Plain fallback words\n</article>", 'Plain fallback words'],
      'the first text node, not the first element text' => ['<article><span>Alpha</span> Beta</article>', 'Alpha'],
      'the first bold node with text for an item without an anchor' =>
        ['<div class="card"><strong>   </strong><span class="story-title">Class based</span><b>Bold later</b></div>',
         'Class based'],
      'a font-semibold node for an item without an anchor' =>
        ['<div class="card"><div class="font-semibold">Semibold item</div></div>', 'Semibold item'],
      'the kicker alone for a card without heading or anchor' =>
        ['<article><span class="kicker">Weather</span><p>Storm ahead.</p></article>', 'Weather']
    }.each do |name, (html, expected)|
      it "is #{name}" do
        expect(item_fields_for(html, item: 'article, .card')[:title]).to eq(expected)
      end
    end

    it 'skips the bold fallback when an anchor is selected' do
      html = '<div class="card"><strong>Bold text</strong><a href="/story">link</a></div>'

      expect(item_fields_for(html, item: '.card')[:title]).to eq('link')
    end

    it 'has no title for an item without text' do
      expect(item_fields_for('<article><img src="x.jpg"></article>')[:title]).to be_nil
    end

    it 'prefixes a trimmed kicker and adds none the headline already opens with', :aggregate_failures do
      padded = '<article><span class="teaser-kicker">   Politics </span><h3>Headline</h3></article>'
      opening = '<article><span class="kicker">Harbor</span><h3>Harbor roundup today</h3></article>'

      expect(item_fields_for(padded)[:title]).to eq('Politics: Headline')
      expect(item_fields_for(opening)[:title]).to eq('Harbor roundup today')
    end

    it 'keeps a kicker the headline only mentions further in' do
      html = '<article><span class="kicker">Harbor</span><h3>New harbor ferry</h3></article>'

      expect(item_fields_for(html)[:title]).to eq('Harbor: New harbor ferry')
    end

    it 'composes a kicker nested in the heading, and none when the kicker wraps the heading', :aggregate_failures do
      nested = '<article><h3><span class="kicker">Update</span><span class="headline">Ferry returns</span></h3>' \
               '</article>'
      wrapped = '<article><div class="overline-block"><h3>Ferry returns</h3><p>Four new stops open.</p></div></article>'

      expect(item_fields_for(nested)[:title]).to eq('Update: Ferry returns')
      expect(item_fields_for(wrapped)[:title]).to eq('Ferry returns')
    end

    it 'drops clock and type-label noise from the kicker and headline' do
      html = '<article><span class="kicker"><time>19:47</time> Harbor :</span>' \
             '<h3><span class="sr-only">Article type: Video</span> Ferry returns</h3></article>'

      expect(item_fields_for(html)[:title]).to eq('Harbor: Ferry returns')
    end
  end

  describe 'url' do
    it 'strips the fragment and surrounding whitespace from the selected anchor href', :aggregate_failures do
      spaced = item_fields_for('<article><a href=" /article/42 #comments ">Story</a></article>')
      fragment = item_fields_for('<article><a href="/article/42#comments">Story</a></article>')

      expect(spaced[:url].to_s).to eq('https://example.com/article/42')
      expect(fragment[:url].to_s).to eq('https://example.com/article/42')
    end

    it 'has none for a card without a link, and an id from its DOM id', :aggregate_failures do
      fields = item_fields_for('<article id="plain"><h2>Plain Story</h2></article>')

      expect(fields.values_at(:id, :url)).to eq(['plain', nil])
    end

    it 'has none for an anchor with an empty href' do
      expect(item_fields_for('<article><a href=""><h2>Story</h2></a></article>')[:url]).to be_nil
    end
  end

  describe 'id' do
    let(:id_for) { ->(html, item: 'article') { item_fields_for(html, item:)[:id] } }

    {
      'the container id' => ['<div class="card" id="container-id"><span id="inner">x</span></div>', 'container-id'],
      'the first descendant id when the container has none' => ['<div class="card"><span id="inner">x</span></div>',
                                                                'inner'],
      'the heading slug when the card has no link' => ['<div class="card"><h2>Headline Here</h2></div>',
                                                       'headline-here'],
      'the link path when the card has a link' =>
        ['<div class="card"><h2>Headline Here</h2><a href="/news/story?ref=home">more</a></div>', '/news/story'],
      'the link path, not its query' => ['<div class="card"><a href="/?id=42">x</a></div>', '/'],
      'a slug without leading or trailing separators' => ['<div class="card"><h2>-- Hello, World! --</h2></div>',
                                                          'hello-world'],
      'the slug of the heading rather than the first text' =>
        ['<div class="card"><p>Intro</p><h2>Headline Here</h2></div>', 'headline-here'],
      'a hash of the heading when its slug is empty' =>
        ['<div class="card"><h2>!!!</h2></div>', Zlib.crc32('!!!').to_s(36)],
      'the first non-blank text when the heading is blank' =>
        ['<div class="card"><h2>   </h2><p>  Body text  </p></div>', 'body-text'],
      'the slug of the first text when there is no heading' => ['<div class="card">Some   content</div>',
                                                                'some-content'],
      'the first non-blank text in document order' =>
        ['<div class="card"><span>First</span><span>Second</span></div>', 'first'],
      'a slug of the title-classed node of an item without heading and link' =>
        ['<div class="card"><p>Intro</p><strong class="title">Fallback Article Title</strong></div>',
         'fallback-article-title'],
      'nothing for an item without text' => ['<div class="card">   </div>', nil]
    }.each do |name, (html, expected)|
      it "is #{name}" do
        expect(id_for.call(html, item: '.card')).to eq(expected)
      end
    end

    it 'is a stable hash of a non-ASCII heading while the text around it changes', :aggregate_failures do
      ids = ['3 ч назад', '5 ч назад'].map do |age|
        id_for.call("<div><h2>日本語の見出し</h2>#{age}</div>", item: 'div')
      end

      expect(ids.first).to eq(Zlib.crc32('日本語の見出し').to_s(36))
      expect(ids.uniq.size).to eq(1)
    end

    it 'is a hash of an item whose text has no heading and no slug characters' do
      expect(id_for.call('<div class="card">日本語</div>', item: '.card')).to eq(Zlib.crc32('日本語').to_s(36))
    end
  end

  describe 'description and date from the parent card' do
    let(:card) do
      lambda do |inner, item|
        item_fields_for(%(<div class="card">#{inner}</div>), item:)
      end
    end
    let(:date) { '<time datetime="2024-02-24T12:00:00+00:00">Feb 24</time>' }

    it 'takes the summary and date of the parent card for a heading item', :aggregate_failures do
      fields = card.call("<h3><a href=\"/story/1\">Card Title</a></h3>#{date}<p>Card summary text</p>", 'h3')

      expect(fields[:description]).to eq('Card summary text')
      expect(fields[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end

    it 'takes the summary and date of the parent card for a bare anchor item', :aggregate_failures do
      fields = card.call("<a href=\"/story/1\"><img src=\"x.jpg\"></a>#{date}<p>Card summary text</p>", '.card a')

      expect(fields[:description]).to eq('Card summary text')
      expect(fields[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end

    it 'does not walk from an item that is neither heading nor anchor', :aggregate_failures do
      fields = card.call("<div class=\"item\"><img src=\"x.jpg\"></div>#{date}<p>Card summary text</p>", '.item')

      expect(fields.values_at(:published_at, :description)).to eq([nil, nil])
    end

    it 'does not walk when the heading item already carries a date', :aggregate_failures do
      fields = card.call("<h3><a href=\"/story/1\">Card Title</a>#{date}</h3><p>Card summary text</p>", 'h3')

      expect(fields[:description]).to be_nil
      expect(fields[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end

    it 'does not walk to a parent holding several headings, whether or not they share a link', :aggregate_failures do
      %w[/story/2 /story/1].each do |other|
        fields = card.call("<h3><a href=\"/story/1\">Card Title</a></h3><h3><a href=\"#{other}\">Other</a></h3>" \
                           "#{date}<p>Card summary text</p>", 'h3')

        expect(fields.values_at(:description, :published_at)).to eq([nil, nil])
      end
    end

    it 'walks past a wrapper whose only child is the heading', :aggregate_failures do
      fields = card.call("<div class=\"inner\"><h3><a href=\"/story/1\">Card Title</a></h3></div>#{date}" \
                         '<p>Card summary text</p>', 'h3')

      expect(fields[:description]).to eq('Card summary text')
      expect(fields[:published_at].to_s).to eq('2024-02-24T12:00:00+00:00')
    end

    it 'walks past wrappers that nest the heading item' do
      fields = card.call('<div class="inner"><div class="wrap"><h3><a href="/story/1">Card Title</a></h3></div>' \
                         "</div>#{date}<p>Card summary text</p>", 'h3')

      expect(fields[:description]).to eq('Card summary text')
    end

    it 'walks past a landmark wrapper to the parent card' do
      fields = card.call("<aside><h3><a href=\"/story/1\">Card Title</a></h3></aside>#{date}<p>Card summary text</p>",
                         'h3')

      expect(fields[:description]).to eq('Card summary text')
    end

    it 'takes categories from the parent card after walking to it' do
      fields = card.call("<h3><a href=\"/story/1\">Card Title</a></h3><span class=\"category\">Politics</span>#{date}" \
                         '<p>Card summary text</p>', 'h3')

      expect(fields[:categories]).to include('Politics')
    end

    it 'takes categories from the item when no walk happens' do
      html = '<article><h3>Headline</h3><span class="category">Politics</span><p>Body</p></article>'

      expect(item_fields_for(html)[:categories]).to include('Politics')
    end

    it 'logs the aborted walk at the crowded parent', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      messages = []
      allow(Html2rss::Log).to receive(:debug) { |&block| messages << block&.call }

      fields = card.call('<h3><a href="/story/1">Card Title</a></h3><h3><a href="/story/2">Other</a></h3>' \
                         '<p>Card summary text</p>', 'h3')

      expect(fields[:description]).to be_nil
      expect(messages).to include('parent-walk abort at div')
    end

    it 'stops the walk without raising when the heading item has no usable parent', :aggregate_failures do
      messages = []
      allow(Html2rss::Log).to receive(:debug) { |&block| messages << block&.call }

      fields = item_fields_for('<html><body><h3>Lonely</h3></body></html>', item: 'h3')

      expect(fields[:published_at]).to be_nil
      expect(messages).to include('parent-walk abort at body')
    end
  end

  describe 'description' do
    it 'excludes the selected anchor text, the title line and inline anchors', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      read_more = item_fields_for('<article><h2>Headline</h2><p>Body text</p><a href="/story/9">Read more</a>' \
                                  '</article>')
      inline = item_fields_for('<article><h2>Headline</h2><p>Body <a href="/story/3">Story about cats</a> text</p>' \
                               '</article>')
      repeated = item_fields_for('<article><h2><a href="/news/7">Rich Story</a></h2><p>Rich Story</p><p>Rich text</p>' \
                                 '</article>')

      expect(read_more[:description]).to eq('Body text')
      expect(inline[:description]).to eq('Body text')
      expect(repeated[:description]).to eq('Rich text')
    end
  end

  describe 'image' do
    let(:image_for) { ->(html) { item_fields_for(html)[:image].to_s } }

    {
      'the first remote img src, skipping data: URIs' =>
        ['<article><img src="data:image/jpeg;base64,/9j/4AAQ" alt="d"><img src="image.jpg"></article>',
         'https://example.com/image.jpg'],
      'the first of several remote img sources' =>
        ['<article><img src="data:image/gif;base64,AAAA"><img src="first.jpg"><img src="second.jpg"></article>',
         'https://example.com/first.jpg'],
      'a relative path that merely starts with data, still skipping the data: URI' =>
        ['<article><img src="data:image/gif;base64,R0lG"><img src="data/hero.jpg"></article>',
         'https://example.com/data/hero.jpg'],
      'the largest srcset source, commas in the url included' =>
        ['<article><img srcset="image,with,commas.jpg 256w, another,image,with,commas.jpg 1w"></article>',
         'https://example.com/image,with,commas.jpg'],
      'the largest source of a picture over its img src' =>
        ['<article><picture><source srcset="/a.200w.jpg 200w, /a.2000w.jpg 2000w, /a.1200w.jpg 1200w">' \
         '<img src="/a.20w.jpg"></picture></article>', 'https://example.com/a.2000w.jpg'],
      'the largest srcset source without spaces between sources' =>
        ['<article><picture><img srcset="/i.88w.jpg 88w,/i.175w.jpg 175w"></picture></article>',
         'https://example.com/i.175w.jpg'],
      'a background-image url' =>
        ['<article><div style="background-image: url(&quot;image.jpg&quot;);"></div></article>',
         'https://example.com/image.jpg'],
      'a quoted background url' => ["<article><div style=\"background: url('image.jpg');\"></div></article>",
                                    'https://example.com/image.jpg'],
      'only the style attribute for a url( outside it' =>
        ['<article><div class="url(decoy.jpg)" style="background: url(real.jpg)"></div></article>',
         'https://example.com/real.jpg'],
      'the first usable video poster' =>
        ['<article><video poster="data:image/png;base64,AAAA"></video><video poster=" "></video>' \
         '<video poster="/posters/clip.jpg"><source src="/clip.mp4"></video><video poster="/p/later.jpg"></video>' \
         '</article>', 'https://example.com/posters/clip.jpg'],
      'an image over a video poster' =>
        ['<article><video poster="/posters/clip.jpg"></video><img src="photo.jpg"></article>',
         'https://example.com/photo.jpg'],
      'nothing when the card has no image' => ['<article></article>', '']
    }.each do |name, (html, expected)|
      it "is #{name}" do
        expect(image_for.call(html)).to eq(expected)
      end
    end

    it 'reads an image of a lazy-load noscript fallback' do
      html = '<article><img src="data:image/gif;base64,R0lG"><noscript><img src="/real.png"></noscript></article>'

      expect(image_for.call(html)).to eq('https://example.com/real.png')
    end
  end

  describe 'categories' do
    # A card without a headline would title itself with its first text, a category echo, so one is added.
    let(:categories_for) do
      lambda do |html|
        titled = html.include?('<h') ? html : html.sub(/<article[^>]*>/) { "#{_1}<h2>Headline</h2>" }
        item_fields_for(titled)[:categories]
      end
    end

    {
      'category-related class tokens' =>
        ['<article><div class="category-news">Politics</div><span class="post-tag">Technology</span>' \
         '<div class="article-category">Science</div></article>', %w[Politics Technology Science]],
      'topic, theme and subject class tokens' =>
        ['<article><div class="topic-politics">Politics</div><div class="theme-tech">Tech</div>' \
         '<div class="subject-science">Science</div></article>', %w[Politics Tech Science]],
      'data attributes' =>
        ['<article><div data-category="World News">a</div><span data-tag="Breaking">b</span>' \
         '<div data-topic="Current Events">c</div></article>', ['World News', 'Breaking', 'Current Events']],
      'direct category attributes' =>
        ['<article><div category="Finance">a</div><span tag="Markets">b</span><div topic="Economy">c</div></article>',
         %w[Finance Markets Economy]],
      'the anchors inside a category container' =>
        ['<article><div class="categories"><a href="/c/tech">Technology</a><a href="/c/ai">AI</a></div>' \
         '<div class="tags"><a href="/t/ruby">Ruby</a><a href="/t/rails">Rails</a></div></article>',
         %w[Technology AI Ruby Rails]],
      'category anchors themselves' =>
        ['<article><a class="category-link" href="/c/gadgets">Gadgets</a>' \
         '<a class="post-tag" href="/t/hw">Hardware</a></article>', %w[Gadgets Hardware]],
      'anchors carrying the class without quotes' =>
        ['<article><a class=category-link href=/politics>Politics</a><a class=category-link href=/tech>Technology</a>' \
         '</article>', %w[Politics Technology]],
      'a data attribute value, not the text of a non-category element' =>
        ['<article><div class="card-body" data-category="Politics">Read the full story</div></article>',
         ['Politics']],
      'a data attribute value of an unclassed element' =>
        ['<article><div data-topic=Economy>Ignored visible text</div></article>', ['Economy']],
      'each category once' =>
        ['<article><h2>Headline</h2><div class="category-news">Politics</div><span class="post-tag">Politics</span>' \
         '<div data-category="Politics">Content</div></article>', ['Politics']],
      'News chips, dropping CTA, date and field-label values' =>
        ['<article><div data-category="Read more">CTA</div><div data-tag="12 March 2024">Date</div>' \
         '<div data-topic="Informatietype:">Label</div><span class="post-tag">News</span>' \
         '<span class="post-tag">Valid Tag</span><div data-category="">Content</div></article>',
         ['News', 'Valid Tag']]
    }.each do |name, (html, expected)|
      it "reads #{name}" do
        expect(categories_for.call(html)).to match_array(expected)
      end
    end

    {
      'layout classes that merely contain section or label' =>
        '<article class="p-section__news__teaser"><h2>Headline</h2><div class="label-health">Health</div>' \
        '<span class="section-sports">Sports</span><p>Teaser about the story.</p></article>',
      'the item root classed as a category' =>
        '<article class="category-news"><h2>Root should not become a category</h2><p>Teaser.</p></article>',
      'the item root text classed without quotes' =>
        '<article class=category-root>Root text should not count</article>',
      'a category container wrapping a full teaser' =>
        '<article><div class="categories"><h2>Headline in the wrapper</h2><p>Teaser that is no category.</p></div>' \
        '</article>',
      'a category container wrapping block children' =>
        '<article><div class=post-tags><section>Hidden block</section></div></article>',
      'an item without category elements' => '<article><h1>Title</h1><p>Content without categories</p></article>'
    }.each do |name, html|
      it "reads no category from #{name}" do
        expect(categories_for.call(html)).to eq([])
      end
    end

    it 'drops values echoing the title at every extraction path' do
      html = '<article data-category="Breaking News"><h2>Breaking News</h2>' \
             '<span data-category="Breaking News">Breaking News</span><div class="category">Breaking News</div>' \
             '<div class="category"><a href="/news/breaking">Breaking News</a></div>' \
             '<div class="category">Politics</div></article>'

      expect(categories_for.call(html)).to eq(['Politics'])
    end

    it 'drops a value equal to the title' do
      html = '<article><h2>Election Results Tonight</h2><div class=category-news>Election Results Tonight</div>' \
             '<div class=category-news>Politics</div></article>'

      expect(categories_for.call(html)).to eq(['Politics'])
    end
  end

  describe 'enclosures' do
    let(:enclosures_for) do
      lambda do |html|
        item_fields_for(html, base_url: 'http://example.com')[:enclosures].map do |attributes|
          enclosure = Html2rss::Article::Enclosure.new(**attributes)
          [enclosure.url.to_s, enclosure.type]
        end
      end
    end

    {
      'video and audio sources' =>
        ['<article><video><source src="/v/1.mp4" type="video/mp4"><source src="/v/2.webm" type="video/webm"></video>' \
         '<audio src="/a/1.mp3" type="audio/mpeg"></audio></article>',
         [['http://example.com/v/1.mp4', 'video/mp4'], ['http://example.com/v/2.webm', 'video/webm'],
          ['http://example.com/a/1.mp3', 'audio/mpeg']]],
      'PDF links' =>
        ['<article><a href="/d/report.pdf">Report</a><a href="/f/manual.pdf">Manual</a></article>',
         [['http://example.com/d/report.pdf', 'application/pdf'],
          ['http://example.com/f/manual.pdf', 'application/pdf']]],
      'a video with its own src, and no picture source' =>
        ['<article><video src="/v/clip.mp4" poster="/p/clip.jpg"></video>' \
         '<picture><source src="/i/hero.webp" type="image/webp"></picture></article>',
         [['http://example.com/v/clip.mp4', 'video/mp4']]],
      'archive links typed by extension' =>
        ['<article><a href="/d/data.zip">ZIP</a><a href="/a/backup.tar.gz">TAR</a><a href="/f/package.tgz">TGZ</a>' \
         '</article>',
         [['http://example.com/d/data.zip', 'application/zip'],
          ['http://example.com/a/backup.tar.gz', 'application/gzip'],
          ['http://example.com/f/package.tgz', 'application/gzip']]],
      'file links by path in any case, ignoring the query' =>
        ['<article><a href="/d/REPORT.PDF">Report</a><a href="/d/data.zip?token=1">Data</a>' \
         '<a href="/news/story?file=a.pdf">Story</a></article>',
         [['http://example.com/d/REPORT.PDF', 'application/pdf'], ['http://example.com/d/data.zip?token=1',
                                                                   'application/zip']]],
      'untyped players, typed by their player, keeping a stream playlist' =>
        ['<article><video src="/stream/clip"></video><audio><source src="/stream/episode"></audio>' \
         '<audio src="/play.php?id=7"></audio><video src="/live/index.m3u8"></video></article>',
         [['http://example.com/stream/clip', 'video/mp4'], ['http://example.com/stream/episode', 'audio/mpeg'],
          ['http://example.com/play.php?id=7', 'audio/mpeg'],
          ['http://example.com/live/index.m3u8', 'application/vnd.apple.mpegurl']]],
      'one enclosure per file, the typed one, when a player repeats it' =>
        ['<article><video src="/stream/clip"><source src="/stream/clip" type="video/webm"></video>' \
         '<video src="/v.mp4"><source src="/v.mp4"></video></article>',
         [['http://example.com/stream/clip', 'video/webm'], ['http://example.com/v.mp4', 'video/mp4']]],
      'images' =>
        ['<article><img src="/images/photo.jpg"><img src="/gallery/image.png"></article>',
         [['http://example.com/images/photo.jpg', 'image/jpeg'],
          ['http://example.com/gallery/image.png', 'image/png']]],
      'images, media and file links in document order' =>
        ['<article><img src="/images/hero.jpg"><video><source src="/videos/demo.mp4" type="video/mp4"></video>' \
         '<a href="/documents/guide.pdf">Guide</a><iframe src="/widgets/map.html"></iframe>' \
         '<a href="/news/story">S</a>' \
         '<a href="/downloads/source.zip">Source</a></article>',
         [['http://example.com/images/hero.jpg', 'image/jpeg'], ['http://example.com/videos/demo.mp4', 'video/mp4'],
          ['http://example.com/documents/guide.pdf', 'application/pdf'],
          ['http://example.com/downloads/source.zip', 'application/zip']]],
      'episode files, noscript links included, beside a player' =>
        ['<article><a href="/audio/ep.MP3?src=list" download>Download</a>' \
         '<noscript><p><a href="/video/ep.mp4">Watch offline</a></p></noscript>' \
         '<audio src="/audio/ep.MP3?src=list" type="audio/mpeg"></audio></article>',
         [['http://example.com/audio/ep.MP3?src=list', 'audio/mpeg'],
          ['http://example.com/video/ep.mp4', 'video/mp4']]],
      'an image of a lazy-load noscript fallback' =>
        ['<article><img src="data:image/gif;base64,R0lG"><noscript><img src="/real.png"></noscript></article>',
         [['http://example.com/real.png', 'image/png']]]
    }.each do |name, (html, expected)|
      it "reads #{name}" do
        expect(enclosures_for.call(html)).to eq(expected)
      end
    end

    {
      'a card without media' => '<article><p>No media here</p></article>',
      'sources with empty src attributes' =>
        '<article><video><source src="" type="video/mp4"></video><audio src="" type="audio/mpeg"></audio></article>',
      'embed player frames' =>
        '<article><iframe src="/embeds/video.html"></iframe><iframe src="/e/clip.mp4"></iframe></article>',
      'players and links naming non-web urls' =>
        '<article><video src="blob:https://example.com/x"></video><audio src="javascript:void(0)"></audio>' \
        '<video><source src="data:video/mp4;base64,AAAA"></video><a href="mailto:a@example.com?subject=a.pdf">M</a>' \
        '<a href="ftp://example.com/a.zip">FTP</a></article>',
      'a link with an empty href' => '<article><a href="">Empty PDF Link</a></article>'
    }.each do |name, html|
      it "reads no enclosure from #{name}" do
        expect(enclosures_for.call(html)).to eq([])
      end
    end
  end

  describe 'a card whose SST document is gone' do
    it 'raises the index contract error rather than reading the card without its parents', :aggregate_failures do
      link = build_node(name: :a, href: '/s', text: 'Story')
      segment = build_segment(root: build_node(name: :h3, children: [link]), link:)

      expect { described_class.call(segment, base_url: 'https://example.com', vocabulary: all_scope) }
        .to raise_error(Html2rss::SST::Index::InvalidError, /no live index/)
    end
  end

  describe 'template content' do
    it 'reads nothing from inside a template, which has no SST node', :aggregate_failures do
      html = '<article><h2>Story</h2><template><img src="/hidden.png"><a href="/hidden.pdf">PDF</a></template>' \
             '</article>'
      fields = item_fields_for(html)

      expect(fields.values_at(:image, :enclosures)).to eq([nil, []])
      expect(fields[:title]).to eq('Story')
    end
  end
end
