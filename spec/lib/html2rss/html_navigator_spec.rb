# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::HtmlNavigator do
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
end
