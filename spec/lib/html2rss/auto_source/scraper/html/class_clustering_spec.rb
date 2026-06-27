# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Scraper::Html::ClassClustering do
  describe '.call' do
    let(:html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <body>
          <nav class="nav">
            <a class="nav-link" href="/home">Home</a>
            <a class="nav-link" href="/about">About</a>
            <a class="nav-link" href="/contact">Contact</a>
          </nav>
          <main>
            <!-- Layout wrappers containing multiple elements of other groups -->
            <section class="section-container">
              <div class="row">
                <!-- Our target repeated cards without anchors -->
                <div class="card-item p-4">
                  <span class="card-title font-bold">Release v1.0</span>
                  <p class="card-body">Description text for release one goes here.</p>
                </div>
                <div class="card-item p-4">
                  <span class="card-title font-bold">Release v2.0</span>
                  <p class="card-body">Description text for release two goes here.</p>
                </div>
                <div class="card-item p-4">
                  <span class="card-title font-bold">Release v3.0</span>
                  <p class="card-body">Description text for release three goes here.</p>
                </div>
              </div>
            </section>
          </main>
        </body>
        </html>
      HTML
    end

    let(:parsed_body) { Nokogiri::HTML(html) }

    it 'returns the candidate nodes of the highest scoring class group', :aggregate_failures do
      nodes = described_class.call(parsed_body, minimum_selector_frequency: 3)
      expect(nodes.size).to eq(3)
      expect(nodes.first['class']).to eq('card-item p-4')
    end

    context 'when no class groups meet the minimum frequency' do
      it 'returns an empty array' do
        nodes = described_class.call(parsed_body, minimum_selector_frequency: 5)
        expect(nodes).to eq([])
      end
    end
  end
end
