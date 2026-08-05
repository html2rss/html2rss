# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Scraper::Discovery::ListCandidates do
  describe '#each_article_tag' do
    let(:html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <body>
          <nav>
            <a href="/home">Home</a>
            <a href="/about">About</a>
            <a href="/contact">Contact</a>
          </nav>
          <footer>
            <a href="/privacy">Privacy</a>
            <a href="/terms">Terms</a>
            <a href="/cookies">Cookies</a>
          </footer>
          <main>
            <article><a href="/posts/1">Post 1</a></article>
            <article><a href="/posts/2">Post 2</a></article>
            <article><a href="/posts/3">Post 3</a></article>
          </main>
        </body>
        </html>
      HTML
    end

    let(:parsed_body) { Nokogiri::HTML(html) }
    let(:candidates) do
      described_class.new(parsed_body, minimum_selector_frequency: 3, use_top_selectors: 3)
    end
    let(:anchor_filter) { ->(_node) { true } }
    let(:boundary_condition) { ->(node) { node.name == 'article' } }

    it 'counts same-shaped anchors outside chrome and skips nav/footer', :aggregate_failures do
      pairs = candidates.each_article_tag(anchor_filter:, boundary_condition:).to_a

      expect(pairs.size).to eq(3)
      expect(pairs.map { |article_tag, _| article_tag.at_css('a')['href'] }).to eq(
        %w[/posts/1 /posts/2 /posts/3]
      )
    end
  end
end
