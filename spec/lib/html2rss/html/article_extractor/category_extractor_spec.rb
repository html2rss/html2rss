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
            <div class="category-news">Politics</div>
            <span class="post-tag">Technology</span>
            <div class="article-category">Science</div>
          </article>
        HTML
      end

      it 'extracts categories from elements with category-related class tokens' do
        expect(described_class.call(article_tag)).to contain_exactly('Politics', 'Technology', 'Science')
      end
    end

    context 'when article has additional category patterns' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="topic-politics">Politics</div>
            <div class="theme-tech">Tech</div>
            <div class="subject-science">Science</div>
          </article>
        HTML
      end

      it 'extracts categories from topic/theme/subject class tokens' do
        expect(described_class.call(article_tag)).to contain_exactly('Politics', 'Tech', 'Science')
      end
    end

    context 'when layout classes contain section or label substrings' do
      let(:html_content) do
        <<~HTML
          <article class="p-section__news__teaser">
            <h2>Headline</h2>
            <div class="label-health">Health</div>
            <span class="section-sports">Sports</span>
            <p>Teaser about the story.</p>
          </article>
        HTML
      end

      it 'does not treat layout classes as categories' do
        expect(described_class.call(article_tag)).to eq([])
      end
    end

    context 'when the item root itself has a category class' do
      let(:html_content) do
        <<~HTML
          <article class="category-news">
            <h2>Root should not become a category</h2>
            <p>Teaser paragraph.</p>
          </article>
        HTML
      end

      it 'does not add the item root visible text as a category' do
        expect(described_class.call(article_tag)).to eq([])
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
        expect(described_class.call(article_tag)).to contain_exactly('World News', 'Breaking', 'Current Events')
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
        expect(described_class.call(article_tag)).to contain_exactly('Finance', 'Markets', 'Economy')
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
        expect(described_class.call(article_tag)).to contain_exactly('Technology', 'AI', 'Ruby', 'Rails')
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
        expect(described_class.call(article_tag)).to contain_exactly('Gadgets', 'Hardware')
      end
    end

    context 'when a category container wraps a full teaser' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="categories">
              <h2>Headline in the wrapper</h2>
              <p>Teaser paragraph that must not become a category.</p>
            </div>
          </article>
        HTML
      end

      it 'does not split the container full text into categories' do
        expect(described_class.call(article_tag)).to eq([])
      end
    end

    context 'when article has duplicate categories' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">Politics</div>
            <span class="post-tag">Politics</span>
            <div data-category="Politics">Content</div>
          </article>
        HTML
      end

      it 'returns unique categories' do
        expect(described_class.call(article_tag)).to eq(['Politics'])
      end
    end

    context 'when values are chrome rather than categories' do
      let(:html_content) do
        <<~HTML
          <article>
            <div data-category="Read more">CTA</div>
            <div data-tag="12 March 2024">Date</div>
            <div data-topic="Informatietype:">Label</div>
            <span class="post-tag">Valid Tag</span>
            <div data-category="">Content</div>
          </article>
        HTML
      end

      it 'keeps real tags and drops CTA, date, and field-label values' do
        expect(described_class.call(article_tag)).to eq(['Valid Tag'])
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
        expect(described_class.call(article_tag)).to eq([])
      end
    end

    context 'when article_tag is nil' do
      it 'returns an empty array' do
        expect(described_class.call(nil)).to eq([])
      end
    end
  end
end
