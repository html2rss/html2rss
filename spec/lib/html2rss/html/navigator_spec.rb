# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::Navigator do
  describe '.extract_visible_text' do
    subject(:visible_text) { described_class.extract_visible_text(tag) }

    let(:tag) do
      Nokogiri::HTML.fragment('<div>Hello <span>World</span><script>App = {}</script></div>').at_css('div')
    end

    it 'returns the visible text from the tag and its children' do
      expect(visible_text).to eq('Hello World')
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

    it 'returns nil if target_node is nil' do
      condition = ->(node) { node.name == 'article' }
      result = described_class.parent_until_condition(nil, condition)
      expect(result).to be_nil
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
  end
end
