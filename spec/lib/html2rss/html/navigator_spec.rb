# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::Navigator do
  describe 'tag vocabulary' do
    {
      HEADING_TAGS: [:HEADING_NAMES, %w[h1 h2 h3 h4 h5 h6]],
      IGNORED_CONTAINER_TAGS: [:IGNORED_CONTAINER_NAMES, %w[nav footer header dialog svg script style]]
    }.each do |navigator_const, (tags_const, values)|
      it "derives #{navigator_const} from SST::Tags::#{tags_const} with no delta" do
        derived = Html2rss::SST::Tags.const_get(tags_const).to_set(&:to_s)

        expect(described_class.const_get(navigator_const)).to eq(derived).and eq(Set.new(values))
      end
    end

    it 'builds MAIN_ANCHOR_SELECTOR from SST::Tags::SKIP_HREF_PREFIXES' do
      nots = Html2rss::SST::Tags::SKIP_HREF_PREFIXES.map { |prefix| %[:not([href^="#{prefix}"])] }.join

      expect(described_class::MAIN_ANCHOR_SELECTOR).to eq(%(a[href]:not([href=""])#{nots}))
    end
  end

  describe '.extract_visible_text' do
    subject(:visible_text) { described_class.extract_visible_text(tag) }

    let(:tag) do
      Nokogiri::HTML.fragment('<div>Hello <span>World</span><script>App = {}</script></div>').at_css('div')
    end

    it 'returns the visible text from the tag and its children' do
      expect(visible_text).to eq('Hello World')
    end

    it 'collapses whitespace on a text node' do
      text_node = Nokogiri::HTML.fragment('  Hello   World  ').children.first

      expect(described_class.extract_visible_text(text_node)).to eq('Hello World')
    end

    it 'joins block fragments with a newline by default and with a custom separator', :aggregate_failures do
      list = Nokogiri::HTML.fragment('<div><p>A</p><p>B</p></div>').at_css('div')

      expect(described_class.extract_visible_text(list)).to eq("A\nB")
      expect(described_class.extract_visible_text(list, separator: '|')).to eq('A|B')
    end

    it 'skips the excluded nodes' do
      list = Nokogiri::HTML.fragment('<div><p>A</p><p id="x">B</p></div>').at_css('div')

      expect(described_class.extract_visible_text(list, exclude_nodes: [list.at_css('#x')])).to eq('A')
    end
  end

  describe '.main_anchor_for' do
    let(:article_tag) do
      Nokogiri::HTML.fragment(<<~HTML).at_css('article')
        <article>
          <a href="/category/news">News</a>
          <h2><a href="/article/42">Correct Story</a></h2>
        </article>
      HTML
    end

    it 'returns the first eligible descendant anchor' do
      expect(described_class.main_anchor_for(article_tag)['href']).to eq('/category/news')
    end

    it 'returns the tag itself when it is an eligible anchor' do
      anchor = Nokogiri::HTML.fragment('<a href="/article/7">Story</a>').at_css('a')

      expect(described_class.main_anchor_for(anchor)).to be(anchor)
    end

    it 'returns nil for an ineligible anchor without eligible descendants', :aggregate_failures do
      expect(described_class.main_anchor_for(Nokogiri::HTML.fragment('<a href="#top">Top</a>').at_css('a'))).to be_nil
      expect(described_class.main_anchor_for(Nokogiri::HTML.fragment('<a>Plain</a>').at_css('a'))).to be_nil
    end
  end

  describe '.parent_until_condition' do
    let(:html) do
      <<-HTML
        <div>
          <section>
            <article>
              <p id="target">Some text here</p>
            </article>
          </section>
        </div>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }
    let(:target_node) { document.at_css('#target') }

    it 'returns the node itself if the condition is met' do
      condition = ->(node) { node.name == 'p' }
      result = described_class.parent_until_condition(target_node, condition)
      expect(result).to eq(target_node)
    end

    it 'returns the first parent that satisfies the condition' do
      condition = ->(node) { node.name == 'article' }
      result = described_class.parent_until_condition(target_node, condition)
      expect(result.name).to eq('article')
    end

    it 'returns nil if the node has no parents that satisfy the condition' do
      condition = ->(node) { node.name == 'footer' }
      result = described_class.parent_until_condition(target_node, condition)
      expect(result).to be_nil
    end

    it 'never returns the html element or the document' do
      condition = ->(node) { %w[html document].include?(node.name) }

      expect(described_class.parent_until_condition(target_node, condition)).to be_nil
    end

    it 'returns nil if target_node is nil' do
      condition = ->(node) { node.name == 'article' }
      result = described_class.parent_until_condition(nil, condition)
      expect(result).to be_nil
    end

    it 'never climbs into the XML document', :aggregate_failures do
      xml_target = Nokogiri::XML('<root><p id="t">x</p></root>').at_css('#t')
      document_named = ->(node) { node.name == 'document' }

      expect(described_class.parent_until_condition(xml_target, document_named)).to be_nil
    end
  end

  describe '.usable_card_parent?' do
    let(:document) { Nokogiri::HTML('<body><nav></nav><div class="card"></div></body>') }

    it 'accepts ordinary wrappers and rejects landmarks', :aggregate_failures do
      expect(described_class.usable_card_parent?(document.at_css('div'))).to be(true)
      expect(described_class.usable_card_parent?(document.at_css('nav'))).to be(false)
      expect(described_class.usable_card_parent?(document.at_css('body'))).to be(false)
      expect(described_class.usable_card_parent?(document)).to be(false)
    end

    it 'treats uppercase NAV as a card-walk stop' do
      document = Nokogiri::HTML('<html><body><NAV><a href="/home">Home</a></NAV></body></html>')

      expect(described_class.usable_card_parent?(document.at_css('NAV'))).to be(false)
    end

    it 'stops at page-level header and footer but not at ones inside sectioning content' do # rubocop:disable RSpec/ExampleLength
      document = Nokogiri::HTML('<body><header id="ph"></header><footer id="pf"></footer>' \
                                '<article><header id="ah"></header><footer id="af"></footer></article>' \
                                '<main><div><header id="mh"></header></div></main>' \
                                '<nav><header id="nh"></header></nav></body>')
      usable = %w[ph pf ah af mh nh].to_h { |id| [id, described_class.usable_card_parent?(document.at_css("##{id}"))] }

      expect(usable).to eq('ph' => false, 'pf' => false, 'ah' => true, 'af' => true, 'mh' => true, 'nh' => false)
    end

    it 'stops at utility landmark roles and page-level banner/contentinfo roles' do # rubocop:disable RSpec/ExampleLength
      html = '<body><div id="rn" role="navigation"></div><div id="rc" role="complementary"></div>' \
             '<div id="rd" role="dialog"></div><dialog id="dl"></dialog><div id="rs" role="search"></div>' \
             '<div id="pb" role="banner"></div><article><div id="ab" role="banner"></div></article></body>'
      ids = %w[rn rc rd dl rs pb ab]
      expected = { 'rn' => false, 'rc' => false, 'rd' => false, 'dl' => false, 'rs' => true, 'pb' => false,
                   'ab' => true }
      sst_root = Html2rss::SST::Normalizer.call(html).root
      nokogiri = ids.to_h { |id| [id, described_class.usable_card_parent?(Nokogiri::HTML(html).at_css("##{id}"))] }
      sst = ids.to_h { |id| [id, described_class.usable_card_parent?(sst_root.find_all { _1.attrs.id == id }.first)] }

      expect([nokogiri, sst]).to eq([expected, expected])
    end

    describe 'chrome-scope parity between Nokogiri and SST nodes' do
      let(:html) do
        '<body><header id="page"></header>' \
          '<section><header id="sectioned"></header></section>' \
          '<nav><section><header id="inherited"></header></section></nav>' \
          '<footer><article><footer id="in_footer"></footer></article></footer>' \
          '<div role="navigation"><section><header id="role_nav"></header></section></div>' \
          '<main><nav><header id="main_nav"></header></nav></main></body>'
      end
      let(:ids) { %w[page sectioned inherited in_footer role_nav main_nav] }
      let(:expected) do
        { 'page' => false, 'sectioned' => true, 'inherited' => false, 'in_footer' => false,
          'role_nav' => false, 'main_nav' => true }
      end

      let(:document) { Nokogiri::HTML(html) }
      let(:sst_root) { Html2rss::SST::Normalizer.call(html).root }

      it 'agrees on page-level, sectioned and chrome-inherited headers', :aggregate_failures do
        nokogiri = ids.to_h { |id| [id, described_class.usable_card_parent?(document.at_css("##{id}"))] }
        sst = ids.to_h { |id| [id, described_class.usable_card_parent?(sst_root.find_all { _1.attrs.id == id }.first)] }

        expect(nokogiri).to eq(expected)
        expect(sst).to eq(expected)
      end
    end

    it 'follows the SST chrome index for header and footer nodes', :aggregate_failures do
      doc = Html2rss::SST::Normalizer.call('<html><body><header>H</header><article><header>A</header></article></body></html>')
      page_header, card_header = doc.root.find_all { _1.name == :header }

      expect(described_class.usable_card_parent?(page_header)).to be(false)
      expect(described_class.usable_card_parent?(card_header)).to be(true)
      expect(described_class.usable_card_parent?(Html2rss::SST::Node.build(name: :header))).to be(false)
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

    it 'returns nil after walking to the document' do
      expect(described_class.find_closest_selector_upwards(document.at_css('div'), 'footer')).to be_nil
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

    it 'matches the current node case-insensitively' do
      article = Nokogiri::HTML.fragment('<article><p>x</p></article>').at_css('article')

      expect(described_class.find_tag_in_ancestors(article, 'ARTICLE')).to be(article)
    end

    context 'when the anchor is inside the specified tag' do
      it 'returns the specified tag' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'article')
        expect(article_tag.name).to eq('article')
      end
    end

    context 'when the anchor is not inside the specified tag' do
      it 'returns stop_tag' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'body')
        expect(article_tag).to be document.at_css('html > body, body')
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

  describe '.descendant_of?' do
    let(:document) do
      Nokogiri::HTML <<-HTML
        <div id="parent">
          <section id="child">
            <p id="grandchild">Content</p>
          </section>
          <div id="other"></div>
        </div>
      HTML
    end

    it 'returns true if the node is a direct child' do
      expect(described_class.descendant_of?(document.at_css('#child'), document.at_css('#parent'))).to be(true)
    end

    it 'returns true if the node is a nested grandchild' do
      expect(described_class.descendant_of?(document.at_css('#grandchild'), document.at_css('#parent'))).to be(true)
    end

    it 'returns false if the node is not a descendant', :aggregate_failures do
      child = document.at_css('#child')
      expect(described_class.descendant_of?(document.at_css('#parent'), child)).to be(false)
      expect(described_class.descendant_of?(document.at_css('#other'), child)).to be(false)
    end

    it 'returns false for the node itself and for the document', :aggregate_failures do
      parent = document.at_css('#parent')

      expect(described_class.descendant_of?(parent, parent)).to be(false)
      expect(described_class.descendant_of?(document, parent)).to be(false)
    end
  end
end
