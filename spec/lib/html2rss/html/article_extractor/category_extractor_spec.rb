# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::ArticleExtractor::CategoryExtractor do
  describe '.call' do
    let(:html) { Nokogiri::HTML.fragment(html_content) }
    let(:article_tag) { html.at_css('article') }

    context 'when article has category classes' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">News</div>
            <span class="post-tag">Technology</span>
            <div class="article-category">Science</div>
          </article>
        HTML
      end

      it 'extracts categories from elements with category-related class names' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('News', 'Technology', 'Science')
      end
    end

    context 'when article has additional category patterns' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="topic-politics">Politics</div>
            <span class="section-sports">Sports</span>
            <div class="label-health">Health</div>
            <div class="theme-tech">Tech</div>
            <div class="subject-science">Science</div>
          </article>
        HTML
      end

      it 'extracts categories from additional category patterns' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Politics', 'Sports', 'Health', 'Tech', 'Science')
      end
    end

    context 'when article has category data attributes' do
      let(:html_content) do
        <<~HTML
          <article>
            <div data-category="World News">Article content</div>
            <span data-tag="Breaking">More content</span>
            <div data-topic="Current Events">Even more content</div>
          </article>
        HTML
      end

      it 'extracts categories from data attributes' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('World News', 'Breaking', 'Current Events')
      end
    end

    context 'when article has direct category attributes' do
      let(:html_content) do
        <<~HTML
          <article>
            <div category="Finance">Article content</div>
            <span tag="Markets">More content</span>
            <div topic="Economy">Even more content</div>
          </article>
        HTML
      end

      it 'extracts categories from direct attributes' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Finance', 'Markets', 'Economy')
      end
    end

    context 'when category elements contain anchor tags' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="categories">
              <a href="/category/tech">Technology</a>
              <a href="/category/ai">AI</a>
            </div>
            <div class="tags">
              <a href="/tag/ruby">Ruby</a>
              <a href="/tag/rails">Rails</a>
            </div>
          </article>
        HTML
      end

      it 'extracts text from individual anchor tags within category containers' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Technology', 'AI', 'Ruby', 'Rails')
      end
    end

    context 'when category element itself is an anchor tag' do
      let(:html_content) do
        <<~HTML
          <article>
            <a class="category-link" href="/category/gadgets">Gadgets</a>
            <a class="post-tag" href="/tag/hardware">Hardware</a>
          </article>
        HTML
      end

      it 'extracts text from the category anchor tags directly' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Gadgets', 'Hardware')
      end
    end

    context 'when category text contains multiple items separated by newlines' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="categories">
              Web Development
              Mobile Apps
              Cloud Computing
            </div>
          </article>
        HTML
      end

      it 'splits categories by newlines and trims whitespace' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Web Development', 'Mobile Apps', 'Cloud Computing')
      end
    end

    context 'when article has duplicate categories' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">News</div>
            <span class="post-tag">News</span>
            <div data-category="News">Content</div>
          </article>
        HTML
      end

      it 'returns unique categories' do
        categories = described_class.call(article_tag)
        expect(categories).to eq(['News'])
      end
    end

    context 'when article has empty or whitespace-only category values' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-empty">   </div>
            <span class="post-tag">Valid Tag</span>
            <div data-category="">Content</div>
          </article>
        HTML
      end

      it 'filters out empty and whitespace-only categories' do
        categories = described_class.call(article_tag)
        expect(categories).to eq(['Valid Tag'])
      end
    end

    context 'when article has no category elements' do
      let(:html_content) do
        <<~HTML
          <article>
            <h1>Title</h1>
            <p>Content without any category-related elements</p>
          </article>
        HTML
      end

      it 'returns an empty array' do
        categories = described_class.call(article_tag)
        expect(categories).to eq([])
      end
    end

    context 'when article_tag is nil' do
      it 'returns an empty array' do
        categories = described_class.call(nil)
        expect(categories).to eq([])
      end
    end
  end
end
