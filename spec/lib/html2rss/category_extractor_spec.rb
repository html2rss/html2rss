# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::CategoryExtractor do
  describe '.call' do
    let(:html) { Html2rss::HtmlParser.parse_html_fragment(html_content) }
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

    context 'when article has tag classes' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="post-tags">Sports</div>
            <span class="tag-item">Politics</span>
            <div class="article-tag">Health</div>
          </article>
        HTML
      end

      it 'extracts categories from elements with tag-related class names' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Sports', 'Politics', 'Health')
      end
    end

    context 'when article has data attributes with category info' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="post-topic" data-topic="Business">Business News</div>
            <span class="item-tag" data-tag="Finance">Finance Update</span>
            <div class="content-category" data-category="Economy">Economy Report</div>
          </article>
        HTML
      end

      it 'extracts categories from both text content and data attributes' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('Business', 'Business News', 'Economy', 'Economy Report', 'Finance',
                                              'Finance Update')
      end
    end

    context 'when article has mixed category sources' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">News</div>
            <span class="post-tag">Technology</span>
            <div class="post" data-category="Science">Post</div>
            <span class="item" data-tag="Health">Item</span>
          </article>
        HTML
      end

      it 'extracts categories from all sources' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('News', 'Technology', 'Science', 'Health')
      end
    end

    context 'when article has empty or whitespace-only categories' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">News</div>
            <span class="post-tag">   </span>
            <div class="article-category"></div>
            <span class="tag-item">Technology</span>
          </article>
        HTML
      end

      it 'filters out empty categories' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('News', 'Technology')
      end
    end

    context 'when article has duplicate categories' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">News</div>
            <span class="post-tag">Technology</span>
            <div class="article-category">News</div>
            <span class="tag-item">Technology</span>
          </article>
        HTML
      end

      it 'removes duplicate categories' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('News', 'Technology')
      end
    end

    context 'when article has no category-related elements' do
      let(:html_content) do
        <<~HTML
          <article>
            <h1>Title</h1>
            <p>Content</p>
            <div class="author">Author</div>
          </article>
        HTML
      end

      it 'returns empty array' do
        categories = described_class.call(article_tag)
        expect(categories).to eq([])
      end
    end

    context 'when article_tag is nil' do
      it 'returns empty array' do
        categories = described_class.call(nil)
        expect(categories).to eq([])
      end
    end

    context 'when categories have extra whitespace' do
      let(:html_content) do
        <<~HTML
          <article>
            <div class="category-news">  News  </div>
            <span class="post-tag">  Technology  </span>
          </article>
        HTML
      end

      it 'strips whitespace from categories' do
        categories = described_class.call(article_tag)
        expect(categories).to contain_exactly('News', 'Technology')
      end
    end
  end
end
