# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Html do
  let(:html) do
    <<~HTML
      <!DOCTYPE html>
      <html>

      <head>
        <title>Sample Document</title>
      </head>

      <body>
        <h1>Main Heading</h1>
        <article>
          <h2>Article 1 Headline</h2>
          <p>
            Teaser for article 1.
            <a href="article1/">Read more</a>
          </p>
        </article>
        <article>
          <h2>Article 2 Headline</h2>
          <p>
            Teaser for article 2.
            <a href="article2/">Read more</a>
          </p>
        </article>
      </body>

      </html>
    HTML
  end
  let(:parsed_body) do
    Nokogiri::HTML(html)
  end

  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:html) }
  end

  describe '.articles?(parsed_body)' do
    subject(:articles?) { described_class.articles?(parsed_body) }

    it { is_expected.to be_truthy }
  end

  describe '#each' do
    subject(:articles) { described_class.new(parsed_body, url: 'http://example.com') }

    let(:first_article) do
      { title: 'Article 1 Headline',
        url: be_a(Addressable::URI),
        image: nil,
        description: 'Article 1 Headline Teaser for article 1. Read more',
        id: '/article1/',
        published_at: nil,
        enclosure: nil }
    end
    let(:second_article) do
      { title: 'Article 2 Headline',
        url: be_a(Addressable::URI),
        image: nil,
        description: 'Article 2 Headline Teaser for article 2. Read more',
        id: '/article2/',
        published_at: nil,
        enclosure: nil }
    end

    it 'yields articles' do
      expect { |b| articles.each(&b) }.to yield_control.twice
    end

    it 'contains the two articles', :aggregate_failures do
      first, last = articles.to_a

      expect(first).to include(first_article)
      expect(last).to include(second_article)
    end

    context 'when parsed_body does not wrap article in an element' do
      let(:html) do
        <<~HTML
          <!doctype html>
          <html lang="de"><meta charset="utf-8">
          <h3>Sun Oct 27 2024</h3>
          <ul>
            <li>
              <a href="?ts=deadh0rse">[Plonk]</a>
              <a href="https://www.tagesschau.de/wirtschaft/verbraucher/kosten-autos-deutsche-hersteller-100.html">Bla bla bla</a>
          </ul>
          </html>
        HTML
      end

      let(:first_article) do
        { title: nil,
          url: an_instance_of(Addressable::URI),
          image: nil,
          description: '[Plonk]',
          id: '/',
          published_at: nil,
          enclosure: nil }
      end

      let(:second_article) do
        {
          title: nil,
          url: an_instance_of(Addressable::URI),
          image: nil,
          description: 'Bla bla bla',
          id: '/',
          published_at: nil,
          enclosure: nil
        }
      end

      it 'contains the articles with same id', :aggregate_failures do
        first, second  = articles.to_a
        expect(first[:id]).to eq(second[:id])
      end

      it 'contains the first_article' do
        expect(articles.first).to include(first_article)
      end

      it 'contains the second_article' do
        expect(articles.to_a[-1]).to include(second_article)
      end
    end
  end

  describe '.simplify_xpath' do
    it 'converts an XPath selector to an index-less xpath' do
      xpath = '/html/body/div[1]/div[2]/span[3]'
      expected = '/html/body/div/div/span'

      simplified = described_class.simplify_xpath(xpath)

      expect(simplified).to eq(expected)
    end
  end

  describe '#article_tag_condition' do
    let(:html) do
      <<-HTML
      <html>
        <body>
          <nav>
            <a href="link1">Link 1</a>
          </nav>
          <div class="content">
            <a href="link2">Link 2</a>
            <article>
              <a href="link3">Link 3</a>
              <div>
                <a href="link6">Link 6</a>
              </div>
            </article>
          </div>
          <footer>
            <a href="link4">Link 4</a>
          </footer>
          <div class="navigation">
            <a href="link5">Link 5</a>
          </div>
        </body>
      </html>
      HTML
    end

    let(:parsed_body) { Nokogiri::HTML(html) }
    let(:scraper) { described_class.new(parsed_body, url: 'http://example.com') }

    it 'returns false for nodes within ignored tags' do
      node = parsed_body.at_css('nav a')
      expect(scraper.article_tag_condition(node)).to be_falsey
    end

    it 'returns true for body and html tags', :aggregate_failures do
      body_node = parsed_body.at_css('body')
      html_node = parsed_body.at_css('html')
      expect(scraper.article_tag_condition(body_node)).to be_truthy
      expect(scraper.article_tag_condition(html_node)).to be_truthy
    end

    it 'returns true if parent has 2 or more anchor tags' do
      node = parsed_body.at_css('article a')
      expect(scraper.article_tag_condition(node)).to be true
    end

    it 'returns false if none of the conditions are met' do
      node = parsed_body.at_css('footer a')
      expect(scraper.article_tag_condition(node)).to be_falsey
    end

    it 'returns false if parent class matches' do
      node = parsed_body.at_css('.navigation a')
      expect(scraper.article_tag_condition(node)).to be_falsey
    end
  end
end
