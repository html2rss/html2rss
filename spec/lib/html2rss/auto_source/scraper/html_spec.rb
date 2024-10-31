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
        description: 'Teaser for article 1. Read more',
        id: '/article1/',
        published_at: nil }
    end
    let(:second_article) do
      { title: 'Article 2 Headline',
        url: be_a(Addressable::URI),
        image: nil,
        description: 'Teaser for article 2. Read more',
        id: '/article2/',
        published_at: nil }
    end

    it 'yields articles' do
      expect { |b| articles.each(&b) }.to yield_control
    end

    it 'contains two articles' do
      expect(articles.to_a).to contain_exactly(first_article, second_article)
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
        { title: '[Plonk]',
          url: be_a(Addressable::URI),
          image: nil,
          description: 'Bla bla bla',
          id: '/',
          published_at: nil }
      end

      let(:second_article) do
        { title: '[Plonk]',
          url: be_a(Addressable::URI),
          image: nil,
          description: nil,
          id: '/',
          published_at: nil }
      end

      it 'contains the articles with same id', :aggregate_failures do
        first, second = articles.to_a
        expect(articles).to contain_exactly(first_article, second_article)
        expect(first[:id]).to eq(second[:id])
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
end