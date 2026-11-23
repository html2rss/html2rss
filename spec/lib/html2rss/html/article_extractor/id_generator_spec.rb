# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::ArticleExtractor::IdGenerator do
  let(:url) { Html2rss::Url.from_absolute('https://example.com/news/story?ref=home') }

  describe '.call' do
    it 'prefers the container id attribute', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card" id="container-id"><span id="inner">x</span></div>').at_css('.card')

      id = described_class.call(container, heading: nil, url:, selected_anchor: nil)

      expect(id).to eq('container-id')
    end

    it 'uses the first descendant id when the container has none', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><span id="inner">x</span></div>').at_css('.card')

      id = described_class.call(container, heading: nil, url:, selected_anchor: nil)

      expect(id).to eq('inner')
    end

    it 'uses url path and query only when an anchor was selected', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      container = Nokogiri::HTML('<div class="card"><h2>Headline Here</h2></div>').at_css('.card')
      heading = container.at_css('h2')

      without_anchor = described_class.call(container, heading:, url:, selected_anchor: nil)
      with_anchor = described_class.call(container, heading:, url:, selected_anchor: container)

      expect(without_anchor).to eq('headline-here')
      expect(with_anchor).to eq('/news/story')
    end

    it 'prefers the url path over the query when an anchor was selected', :aggregate_failures do
      query_url = Html2rss::Url.from_absolute('https://example.com/?id=42')
      container = Nokogiri::HTML('<div class="card"></div>').at_css('.card')

      id = described_class.call(container, heading: nil, url: query_url, selected_anchor: container)

      expect(id).to eq('/')
    end

    it 'slugifies heading text, trimming leading and trailing separators', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><h2>-- Hello, World! --</h2></div>').at_css('.card')
      heading = container.at_css('h2')

      id = described_class.call(container, heading:, url: nil, selected_anchor: nil)

      expect(id).to eq('hello-world')
    end

    it 'slugifies the given heading rather than the first text node' do
      container = Nokogiri::HTML('<div class="card"><p>Intro</p><h2>Headline Here</h2></div>').at_css('.card')

      id = described_class.call(container, heading: container.at_css('h2'), url: nil, selected_anchor: nil)

      expect(id).to eq('headline-here')
    end

    it 'falls back to the content hash when the heading slug is empty', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><h2>!!!</h2></div>').at_css('.card')
      heading = container.at_css('h2')

      id = described_class.call(container, heading:, url: nil, selected_anchor: nil)

      expect(id).to eq(Zlib.crc32('!!!').to_s(36))
    end

    it 'gives a non-ASCII heading a stable non-nil id', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><h2>日本語の見出し</h2></div>').at_css('.card')
      heading = container.at_css('h2')

      ids = Array.new(2) { described_class.call(container, heading:, url: nil, selected_anchor: nil) }

      expect(ids.first).to match(/\A[0-9a-z]+\z/)
      expect(ids.uniq.size).to eq(1)
    end

    it 'keeps a non-ASCII heading id stable while the card text around it changes', :aggregate_failures do
      cards = ['3 ч назад', '5 ч назад'].map { |age| Nokogiri::HTML(%(<div><h2>日本語の見出し</h2>#{age}</div>)).at_css('div') }
      ids = cards.map { |card| described_class.call(card, heading: card.at_css('h2'), url: nil, selected_anchor: nil) }

      expect(ids.first).to eq(Zlib.crc32('日本語の見出し').to_s(36))
      expect(ids.uniq.size).to eq(1)
    end

    it 'uses the first non-blank text node when the heading is blank', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><h2>   </h2><p>  Body text  </p></div>').at_css('.card')
      heading = container.at_css('h2')

      id = described_class.call(container, heading:, url: nil, selected_anchor: nil)

      expect(id).to eq('body-text')
    end

    it 'slugifies the first text node when no heading is given', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card">Some   content</div>').at_css('.card')

      id = described_class.call(container, heading: nil, url: nil, selected_anchor: nil)

      expect(id).to eq('some-content')
    end

    it 'hashes the node text when the node has no descendant text nodes', :aggregate_failures do
      text_node = Nokogiri::HTML.fragment('hello').children.first

      id = described_class.call(text_node, heading: nil, url: nil, selected_anchor: nil)

      expect(id).to eq('f01gna')
    end

    it 'returns nil for blank content', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card">   </div>').at_css('.card')

      id = described_class.call(container, heading: nil, url: nil, selected_anchor: nil)

      expect(id).to be_nil
    end

    it 'uses the first non-blank text node in document order', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><span>First</span><span>Second</span></div>').at_css('.card')

      id = described_class.call(container, heading: nil, url: nil, selected_anchor: nil)

      expect(id).to eq('first')
    end
  end
end
