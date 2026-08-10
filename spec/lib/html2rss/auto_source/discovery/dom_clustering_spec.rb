# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Discovery::DomClustering do
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

    it 'returns an empty array when no groups meet the minimum frequency' do
      nodes = described_class.call(parsed_body, minimum_selector_frequency: 5)
      expect(nodes).to eq([])
    end

    context 'when candidate cards lack shared classes and require tag structure clustering' do
      let(:tailwind_html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
          <body>
            <nav class="flex items-center justify-between p-4 bg-gray-900 text-white">
              <a class="text-xl font-bold" href="/home">Home</a>
              <a class="hover:underline" href="/about">About</a>
            </nav>
            <main class="max-w-4xl mx-auto py-8 px-4">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div class="rounded-xl bg-slate-800 p-6 shadow-lg border border-slate-700">
                  <h3 class="text-xl font-semibold text-white">Tailwind Article One</h3>
                  <p class="mt-2 text-slate-300">Detailed summary description of the first article post.</p>
                  <a href="/articles/one" class="inline-block mt-4 text-indigo-400 font-medium">Read article</a>
                </div>
                <div class="rounded-xl bg-slate-800 p-6 shadow-lg border border-slate-700">
                  <h3 class="text-xl font-semibold text-white">Tailwind Article Two</h3>
                  <p class="mt-2 text-slate-300">Detailed summary description of the second article post.</p>
                  <a href="/articles/two" class="inline-block mt-4 text-indigo-400 font-medium">Read article</a>
                </div>
                <div class="rounded-xl bg-slate-800 p-6 shadow-lg border border-slate-700">
                  <h3 class="text-xl font-semibold text-white">Tailwind Article Three</h3>
                  <p class="mt-2 text-slate-300">Detailed summary description of the third article post.</p>
                  <a href="/articles/three" class="inline-block mt-4 text-indigo-400 font-medium">Read article</a>
                </div>
              </div>
            </main>
          </body>
          </html>
        HTML
      end

      let(:parsed_tailwind_body) { Nokogiri::HTML(tailwind_html) }

      it 'returns candidate nodes of the top-scoring structural tag group', :aggregate_failures do
        nodes = described_class.call(parsed_tailwind_body, minimum_selector_frequency: 3)
        expect(nodes.size).to eq(3)
        expect(nodes.first.at_css('h3').text).to eq('Tailwind Article One')
      end
    end

    context 'when elements have differing class, id, and style attributes' do
      let(:classless_differing_html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
          <body>
            <main>
              <div>
                <article id="item-1" class="c-a1" style="margin: 10px;">
                  <h2>Unique Post Alpha</h2>
                  <p>Content text for item alpha which is long enough to pass word score.</p>
                  <a href="/alpha">View details</a>
                </article>
                <article id="item-2" class="c-b2" style="margin: 20px;">
                  <h2>Unique Post Beta</h2>
                  <p>Content text for item beta which is long enough to pass word score.</p>
                  <a href="/beta">View details</a>
                </article>
                <article id="item-3" class="c-c3" style="margin: 30px;">
                  <h2>Unique Post Gamma</h2>
                  <p>Content text for item gamma which is long enough to pass word score.</p>
                  <a href="/gamma">View details</a>
                </article>
              </div>
            </main>
          </body>
          </html>
        HTML
      end

      let(:parsed_differing_body) { Nokogiri::HTML(classless_differing_html) }

      it 'ignores class, id, and inline style attributes when computing structural signatures' do
        nodes = described_class.call(parsed_differing_body, minimum_selector_frequency: 3)
        expect(nodes.size).to eq(3)
      end
    end
  end
end
