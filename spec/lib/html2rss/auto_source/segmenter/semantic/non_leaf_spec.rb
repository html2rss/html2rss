# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter::Semantic::NonLeaf do
  subject(:marked) { described_class.call(document_for(html).root).map { _1.attrs.class_names.first }.sort }

  context 'when a container holds a same-name container' do
    let(:html) do
      '<html><body><article class="outer"><article class="inner"><a href="/a">A</a></article></article></body></html>'
    end

    it 'marks the wrapper only' do
      expect(marked).to eq(%w[outer])
    end
  end

  context 'when the same-name container sits deep below' do
    let(:html) do
      <<~HTML
        <html><body><article class="outer"><div><section><article class="inner">
          <a href="/a">A</a></article></section></div></article></body></html>
      HTML
    end

    it 'marks the wrapper through the containers between' do
      expect(marked).to eq(%w[outer])
    end
  end

  context 'when a container holds only containers of other tags' do
    let(:html) do
      <<~HTML
        <html><body><article class="a"><div class="d"><section class="s"><a href="/a">A</a></section></div></article>
        </body></html>
      HTML
    end

    it 'marks none' do
      expect(marked).to be_empty
    end
  end

  context 'with divs that hold no heading' do
    let(:html) do
      <<~HTML
        <html><body><div class="outer"><div class="row"><a href="/a">A</a></div><div class="row">B</div></div>
        </body></html>
      HTML
    end

    it 'marks the wrapper div' do
      expect(marked).to eq(%w[outer])
    end
  end

  context 'when a div holds one linked heading and an info div' do
    let(:html) do
      <<~HTML
        <html><body><div class="card"><h3><a href="/story">Story</a></h3>
          <div class="info"><time>10:00</time><a href="/story">Read more</a></div></div></body></html>
      HTML
    end

    it 'is a card, not marked' do
      expect(marked).to be_empty
    end
  end

  context 'when a card links its heading destination in exactly half of its links' do
    let(:html) do
      <<~HTML
        <html><body><div class="card"><h3><a href="/story">Story</a></h3>
          <div class="info"><a href="/topics/a">Topic</a></div></div></body></html>
      HTML
    end

    it 'is a card, not marked' do
      expect(marked).to be_empty
    end
  end

  context 'when a div holds a linked heading whose destination is a minority of its links' do
    let(:html) do
      <<~HTML
        <html><body><div class="section"><h2><a href="/news/">Latest</a></h2>
          <div class="row"><a href="/news/a">A</a></div><div class="row"><a href="/news/b">B</a></div></div></body></html>
      HTML
    end

    it 'marks the wrapper' do
      expect(marked).to eq(%w[section])
    end
  end

  context 'when a link before the heading is not the heading destination' do
    let(:html) do
      <<~HTML
        <html><body><div class="card"><a href="/tag">Tag</a><h3><a href="/story">Story</a></h3>
          <div class="info"><a href="/story">Read more</a></div></div></body></html>
      HTML
    end

    it 'reads the destination from the heading link' do
      expect(marked).to be_empty
    end
  end

  context 'when a div holds a heading without a link' do
    let(:html) do
      <<~HTML
        <html><body><div class="card"><h3>Story</h3><div class="info"><a href="/story">Read more</a></div></div>
        </body></html>
      HTML
    end

    it 'marks the div' do
      expect(marked).to eq(%w[card])
    end
  end

  context 'when a div holds a heading and no link at all' do
    let(:html) do
      '<html><body><div class="card"><h3>Story</h3><div class="info">10:00</div></div></body></html>'
    end

    it 'marks the div' do
      expect(marked).to eq(%w[card])
    end
  end

  context 'when a div holds two headings' do
    let(:html) do
      <<~HTML
        <html><body><div class="pair"><h3><a href="/a">A</a></h3><h3><a href="/b">B</a></h3>
          <div class="info">x</div></div></body></html>
      HTML
    end

    it 'marks the div' do
      expect(marked).to eq(%w[pair])
    end
  end

  context 'when a div holds no heading but links and an inner div' do
    let(:html) do
      '<html><body><div class="plain"><a href="/a">A</a><div class="info">x</div></div></body></html>'
    end

    it 'marks the div' do
      expect(marked).to eq(%w[plain])
    end
  end

  context 'when an inner div holds the heading' do
    let(:html) do
      <<~HTML
        <html><body><div class="outer"><div class="inner"><h3><a href="/story">Story</a></h3></div></div></body></html>
      HTML
    end

    it 'marks the outer div' do
      expect(marked).to eq(%w[outer])
    end
  end

  context 'when a div far below a non-div child holds the heading' do
    let(:html) do
      <<~HTML
        <html><body><div class="outer"><section><div class="inner">
          <h3><a href="/story">Story</a></h3></div></section></div></body></html>
      HTML
    end

    it 'marks the outer div' do
      expect(marked).to eq(%w[outer])
    end
  end

  context 'when a card div sits inside a larger card grid' do
    let(:html) do
      <<~HTML
        <html><body><div class="grid">
          <div class="card"><h3><a href="/a">A</a></h3><div class="info">x</div></div>
          <div class="card"><h3><a href="/b">B</a></h3><div class="info">y</div></div>
        </div></body></html>
      HTML
    end

    it 'marks the grid and leaves each card', :aggregate_failures do
      expect(marked).to eq(%w[grid])
    end
  end

  context 'when a list item with one linked heading holds another list item' do
    let(:html) do
      <<~HTML
        <html><body><ul><li class="outer"><h3><a href="/a">A</a></h3><ul><li class="inner">x</li></ul></li></ul></body></html>
      HTML
    end

    it 'marks the list item: only divs take the card exception' do
      expect(marked).to eq(%w[outer])
    end
  end
end
