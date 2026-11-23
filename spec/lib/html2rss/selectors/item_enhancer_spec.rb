# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::ItemEnhancer do
  subject(:enhancer) { enhancer_for.call(parsed) }

  let(:enhancer_for) do
    lambda do |page|
      described_class.new(page, base_url: Html2rss::Url.from_absolute('https://example.com'), time_zone: 'UTC',
                                vocabulary: all_scope)
    end
  end

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

    it 'reads an item inside a noscript, which a browser without script shows' do
      page = Nokogiri::HTML('<body><noscript><div class="card"><h3><a href="/n">Plain</a></h3></div></noscript></body>')

      expect(enhancer_for.call(page).fields_for(page.at_css('.card'))[:title]).to eq('Plain')
    end

    context 'when the item has no SST node' do
      let(:html) do
        '<html><body><template><div class="card"><a href="/t">In a template</a></div></template></body></html>'
      end

      it 'returns nil and logs the item as skipped', :aggregate_failures do
        allow(Html2rss::Log).to receive(:debug)

        expect(enhancer.fields_for(parsed.at_css('.card'))).to be_nil
        expect(Html2rss::Log).to have_received(:debug)
          .with({ event_name: 'selectors.enhance.skipped', reason: 'unmapped_item', node: 'div' }.to_json)
      end
    end

    context 'when the page has several roots, as an HTML fragment parsed from JSON can' do
      let(:parsed) do
        Nokogiri::HTML5.fragment('<p class="card"><a href="/one">One</a></p><p class="card"><a href="/two">Two</a></p>')
      end

      it 'reads the items of the first root only', :aggregate_failures do
        first, second = parsed.css('.card')

        expect(enhancer.fields_for(first)[:title]).to eq('One')
        expect(enhancer.fields_for(second)).to be_nil
      end

      it 'logs the unread item at debug, and nothing at warn', :aggregate_failures do
        allow(Html2rss::Log).to receive(:warn)
        allow(Html2rss::Log).to receive(:debug)

        enhancer.fields_for(parsed.css('.card').last)

        expect(Html2rss::Log).not_to have_received(:warn)
        expect(Html2rss::Log).to have_received(:debug).with(/"reason":"unmapped_item"/)
      end
    end

    context 'when no SST tree can be built from the page' do
      let(:parsed) { Nokogiri::XML('<!-- no element -->') }

      it 'warns once and leaves every item unread', :aggregate_failures do
        allow(Html2rss::Log).to receive(:warn)
        allow(Html2rss::Log).to receive(:debug)
        item = Nokogiri::XML::Node.new('a', parsed)

        expect([enhancer.fields_for(item), enhancer.fields_for(item)]).to eq([nil, nil])
        expect(Html2rss::Log).to have_received(:warn).with({ event_name: 'selectors.enhance.no_document' }.to_json).once
      end
    end
  end
end
