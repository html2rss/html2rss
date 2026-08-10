# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Discovery::StructureClustering do
  describe '.call' do
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

    let(:parsed_body) { Nokogiri::HTML(tailwind_html) }

    it 'returns candidate nodes of the top-scoring structural tag group', :aggregate_failures do
      nodes = described_class.call(parsed_body, minimum_selector_frequency: 3)
      expect(nodes.size).to eq(3)
      expect(nodes.first.at_css('h3').text).to eq('Tailwind Article One')
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

    context 'when no structural groups meet the minimum frequency' do
      it 'returns an empty array' do
        nodes = described_class.call(parsed_body, minimum_selector_frequency: 5)
        expect(nodes).to eq([])
      end
    end
  end

  describe 'ClassClustering fallback integration' do
    let(:unique_classes_html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <body>
          <main>
            <div>
              <div class="hash-hash1">
                <h3>Scoped Title One</h3>
                <p>Detailed summary description text for scoped article one.</p>
                <a href="/post/1">Read post</a>
              </div>
              <div class="hash-hash2">
                <h3>Scoped Title Two</h3>
                <p>Detailed summary description text for scoped article two.</p>
                <a href="/post/2">Read post</a>
              </div>
              <div class="hash-hash3">
                <h3>Scoped Title Three</h3>
                <p>Detailed summary description text for scoped article three.</p>
                <a href="/post/3">Read post</a>
              </div>
            </div>
          </main>
        </body>
        </html>
      HTML
    end

    let(:parsed_body) { Nokogiri::HTML(unique_classes_html) }

    it 'falls back to StructureClustering when ClassClustering produces zero candidate groups', :aggregate_failures do
      nodes = Html2rss::AutoSource::Discovery::ClassClustering.call(parsed_body, minimum_selector_frequency: 3)
      expect(nodes.size).to eq(3)
      expect(nodes.first.at_css('h3').text).to eq('Scoped Title One')
    end
  end
end
