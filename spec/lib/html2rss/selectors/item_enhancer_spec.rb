# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::ItemEnhancer do
  subject(:enhancer) { enhancer_for.call(parsed) }

  let(:enhancer_for) do
    lambda do |page, items = page.css('.card'), time_zone: 'UTC', vocabulary: all_scope|
      described_class.new(items, base_url: Html2rss::Url.from_absolute('https://example.com'), time_zone:, vocabulary:)
    end
  end

  let(:logged) { [] }
  let(:html) do
    <<~HTML
      <html><body>
        <div class="card"><h3><a href="/story/1">Card Title</a></h3><p>Card summary text</p></div>
        <div class="card"><a href="#top">Top</a><h3><a href="/story/2">Second Title</a></h3><p>Second summary</p></div>
      </body></html>
    HTML
  end
  let(:parsed) { Nokogiri::HTML(html) }

  describe '#fields_for' do
    before do
      allow(Html2rss.logger).to receive(:debug?).and_return(true)
      allow(Html2rss::Log).to receive(:debug) { |*text, &message| logged << (message ? message.call : text.first) }
    end

    it 'reads the item, taking its first eligible link as the primary one', :aggregate_failures do
      fields = enhancer.fields_for(parsed.css('.card').last)

      expect(fields[:url].to_s).to eq('https://example.com/story/2')
      expect(fields[:title]).to eq('Second Title')
    end

    it 'builds the SST document once for all items' do
      allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original

      parsed.css('.card').each { enhancer.fields_for(_1) }

      expect(Html2rss::SST::Normalizer).to have_received(:call).once
    end

    it 'keeps the document alive across garbage collection, so a card walk still finds its parent',
       :aggregate_failures do
      first = enhancer.fields_for(parsed.at_css('h3'))
      3.times { GC.start }
      later = enhancer.fields_for(parsed.css('h3').last)

      expect(first[:description]).to eq('Card summary text')
      expect(later[:description]).to eq('Second summary')
    end

    it 'never degrades a page past the node ceiling: an item the heuristic would drop is still read',
       :aggregate_failures do
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 2)
      page = Nokogiri::HTML('<main><p><span class="card"><a href="/s">Story</a></span></p></main>')
      fields = enhancer_for.call(page).fields_for(page.at_css('.card'))

      expect(fields[:title]).to eq('Story')
      expect(fields[:url].to_s).to eq('https://example.com/s')
    end

    it 'reads the item in the page language', :aggregate_failures do
      page = Nokogiri::HTML('<article><b class="kicker">独自</b><h2><a href="/s">港湾計画を発表した</a></h2></article>')
      titles = %i[ja zh-Hans-CN].map do |language|
        enhancer_for.call(page, page.css('article'), vocabulary: Html2rss::Vocabulary[language]).fields_for(page.at_css('article'))[:title]
      end

      expect(titles).to eq(['港湾計画を発表した', '独自: 港湾計画を発表した'])
    end

    it 'reads a naive leftover date in the channel time zone' do
      page = Nokogiri::HTML('<body><article><h2><a href="/s">Story</a></h2><span>12 March 2024</span></article></body>')
      enhancer = enhancer_for.call(page, page.css('article'), time_zone: 'Europe/Berlin')
      fields = enhancer.fields_for(page.at_css('article'))

      expect(fields[:published_at].zone).to eq('+01:00')
    end

    it 'reads an item inside a noscript, which a browser without script shows' do
      page = Nokogiri::HTML('<body><noscript><div class="card"><h3><a href="/n">Plain</a></h3></div></noscript></body>')

      expect(enhancer_for.call(page).fields_for(page.at_css('.card'))[:title]).to eq('Plain')
    end

    describe 'the region normalized for the items' do
      let(:pages) do
        {
          'a list whose cards wrap a thin heading wrapper' =>
            ['h3', '<html><body><main><ul><li><div><h3><a href="/a">A</a></h3></div><p>Summary of A</p></li>' \
                   '<li><div><h3><a href="/b">B</a></h3></div><p>Summary of B</p></li></ul></main></body></html>'],
          'a single card whose thin wrapper sits in a nav beside other content' =>
            ['h3', '<html><body><div><nav><div><h3><a href="/a">A</a></h3></div><div>Other</div></nav>' \
                   '<p>Summary beside the nav</p></div></body></html>'],
          'a header inside a list item, whose chrome scope reads the list' =>
            ['h3', '<html><body><ul><li><header><h3><a href="/a">A</a></h3></header><p>Summary of A</p></li></ul>' \
                   '</body></html>'],
          'a single card under thin wrappers' =>
            ['h3', '<html><body><main><ul><li><div><h3><a href="/a">A</a></h3></div></li></ul>' \
                   '<p>Summary beside the list</p></main></body></html>'],
          'a thin wrapper beside a script, which is no SST node' =>
            ['h3', '<html><body><main><ul><li><div><h3><a href="/a">A</a></h3></div><script>x()</script></li></ul>' \
                   '<p>Summary beside the list</p></main></body></html>'],
          'headings straight under the body' =>
            ['h2', '<html><body><h2><a href="/a">A</a></h2><p>Only text</p><h2><a href="/b">B</a></h2></body></html>'],
          'headings in a page header, which is chrome' =>
            ['h2', '<html><body><header><h2><a href="/a">A</a></h2><p>Tagline</p></header><main><section>' \
                   '<h2><a href="/b">B</a></h2><p>Summary of B</p></section></main></body></html>'],
          'a card in a header inside an article' =>
            ['h2', '<html><body><article><header><h2><a href="/a">A</a></h2><p>Summary of A</p></header>' \
                   '</article></body></html>'],
          'headings inside a nav' =>
            ['h3', '<html><body><nav><div><h3><a href="/a">A</a></h3></div><div><h3><a href="/b">B</a></h3>' \
                   '<p>Summary of B</p></div></nav></body></html>']
        }
      end

      it 'reads each item as the whole page would', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        pages.each_value do |(selector, page)|
          items = Nokogiri::HTML(page).css(selector)
          enhancer = enhancer_for.call(items.first.document, items)
          whole = Array.new(items.size) { item_fields_for(page, item: selector, nth: _1) }

          expect(items.map { enhancer.fields_for(_1) }).to eq(whole)
        end
      end

      it 'normalizes the lowest element holding the items and their parent cards, seeded with its scope' do # rubocop:disable RSpec/ExampleLength
        page = Nokogiri::HTML('<html><body><header><p>Page</p></header><main><ul><li><h3><a href="/a">A</a></h3></li>' \
                              '<li><h3><a href="/b">B</a></h3></li></ul></main><footer>Page end</footer></body></html>')
        allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original
        enhancer_for.call(page, page.css('h3')).fields_for(page.at_css('h3'))

        expect(Html2rss::SST::Normalizer).to have_received(:call)
          .with(page.at_css('ul'), hash_including(items: true, within: :sectioned)).once
      end
    end

    it 'holds the document of an item read apart, as it holds the page document', :aggregate_failures do
      page = Nokogiri::HTML('<html><body><template><h3 class="card"><a href="/a">A</a></h3></template></body></html>')
      enhancer = enhancer_for.call(page)

      expect(enhancer.fields_for(page.at_css('.card'))[:title]).to eq('A')
      expect(enhancer.instance_variable_get(:@alone).map { _1.root.name }).to eq([:h3])
    end

    it 'stops the walk at a parent that holds a noscript, which the items keep', :aggregate_failures do
      page = Nokogiri::HTML('<html><body><ul><li><div><h3><a href="/a">A</a></h3></div><noscript>x</noscript></li>' \
                            '</ul></body></html>')
      allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original
      enhancer_for.call(page, page.css('h3')).fields_for(page.at_css('h3'))

      expect(Html2rss::SST::Normalizer).to have_received(:call).with(page.at_css('li'), anything)
    end

    it 'reads an item of no selected set by itself' do
      page = Nokogiri::HTML('<div class="card"><a href="/a">A</a></div>')

      expect(enhancer_for.call(page, page.css('.none')).fields_for(page.at_css('.card'))[:title]).to eq('A')
    end

    context 'when the item has no SST node' do
      let(:html) do
        '<html><body><template><div class="card"><a href="/t">In a template</a></div></template></body></html>'
      end

      it 'reads the item from its own root and logs that at debug', :aggregate_failures do
        fields = enhancer.fields_for(parsed.at_css('.card'))

        expect(fields.values_at(:title, :url).map(&:to_s)).to eq(['In a template', 'https://example.com/t'])
        expect(logged).to eq([{ event_name: 'selectors.enhance.alone', node: 'div' }.to_json])
      end

      it 'seeds the chrome scope its ancestors give it', :aggregate_failures do
        page = Nokogiri::HTML('<template><nav><div class="card"><a href="/n">Nav card</a></div></nav></template>')
        allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original

        expect(enhancer_for.call(page).fields_for(page.at_css('.card'))[:title]).to eq('Nav card')
        expect(Html2rss::SST::Normalizer).to have_received(:call)
          .with(page.at_css('.card'), hash_including(items: true, within: :chrome))
      end
    end

    context 'when the page has several roots, as an HTML fragment parsed from JSON can' do
      let(:parsed) do
        Nokogiri::HTML5.fragment('<p class="card"><a href="/one">One</a></p><p class="card"><a href="/two">Two</a></p>')
      end

      it 'reads the items of every root, each by itself', :aggregate_failures do
        first, second = parsed.css('.card')
        allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original

        expect(enhancer.fields_for(first)[:title]).to eq('One')
        expect(enhancer.fields_for(second)[:title]).to eq('Two')
        expect(Html2rss::SST::Normalizer).to have_received(:call).twice
      end

      it 'logs the item read apart at debug, and nothing at warn', :aggregate_failures do
        allow(Html2rss::Log).to receive(:warn)

        enhancer.fields_for(parsed.css('.card').last)

        expect(Html2rss::Log).not_to have_received(:warn)
        expect(logged).to include({ event_name: 'selectors.enhance.alone', node: 'p' }.to_json)
      end

      it 'keeps every document alive across garbage collection, so a card walk still finds its parent',
         :aggregate_failures do
        card = parsed.css('.card').last
        enhancer.fields_for(card)
        3.times { GC.start }

        expect(enhancer.fields_for(card)[:title]).to eq('Two')
      end
    end

    context 'when no SST tree can be built from the page' do
      let(:parsed) { Nokogiri::XML('<!-- no element -->') }

      it 'reads an item by itself, and skips one that is no SST node at all', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        anchor = Nokogiri::XML::Node.new('a', parsed)
        script = Nokogiri::XML::Node.new('script', parsed)
        enhancer = enhancer_for.call(parsed, Nokogiri::XML::NodeSet.new(parsed, [anchor, script]))

        expect(enhancer.fields_for(anchor)).to include(url: nil, title: nil)
        expect(enhancer.fields_for(script)).to be_nil
        expect(enhancer.instance_variable_get(:@alone).size).to eq(1)
        expect(logged.last).to eq({ event_name: 'selectors.enhance.skipped', node: 'script' }.to_json)
      end
    end
  end
end
