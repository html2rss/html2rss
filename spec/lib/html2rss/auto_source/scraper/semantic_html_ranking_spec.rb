# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com') }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/multi_link_block.html')) }
    let(:articles) { new.each.to_a }

    it 'selects the best anchor for each block', :aggregate_failures do
      # Block 1: Should prefer /article/1 over /category/news
      article_1 = articles.find { |a| a[:url].to_s == 'https://page.com/article/1' }
      expect(article_1).not_to be_nil
      expect(article_1[:title]).to eq('Main Article Title')

      expect(articles.find { |a| a[:url].to_s == 'https://page.com/category/news' }).to be_nil
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/article/1#comments' }).to be_nil
      expect(articles.find { |a| a[:url].to_s == 'https://twitter.com/share?url=...' }).to be_nil

      # Block 2: Utility-only links should not produce an article
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/about' }).to be_nil
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/contact' }).to be_nil
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/newsletter/signup' }).to be_nil

      # Block 3: Should prefer /article/3
      article_3 = articles.find { |a| a[:url].to_s == 'https://page.com/article/3' }
      expect(article_3).not_to be_nil
      expect(article_3[:title]).to eq('Correct Title Link')
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/gallery/3' }).to be_nil
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/author/jane' }).to be_nil

      # Block 4: Should prefer the article link over icon-only and utility text links
      article_4 = articles.find { |a| a[:url].to_s == 'https://page.com/article/4' }
      expect(article_4).not_to be_nil
      expect(article_4[:title]).to eq('Actual Article Text')
      expect(articles.find { |a| a[:url].to_s == 'https://page.com/newsletter/4' }).to be_nil

      expect(articles.map { |a| a[:url].to_s }).to contain_exactly(
        'https://page.com/article/1',
        'https://page.com/article/3',
        'https://page.com/article/4'
      )
    end
  end
end
