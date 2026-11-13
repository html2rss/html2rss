# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter::Semantic do
  let(:hrefs) { segments.map { _1.primary_link.attrs.href } }
  let(:options) { {} }
  let(:segments) do
    Html2rss::AutoSource::Segmenter.call(document_for(html), base_url: 'https://example.com', strategy: :semantic,
                                                             **options)
  end

  context 'when a container wraps another article' do
    let(:html) do
      <<~HTML
        <html><body>
          <article>
            <p>Outer wrapper text that is not the story itself.</p>
            <article><a href="/news/2024/inner-story">Inner story title</a></article>
          </article>
        </body></html>
      HTML
    end

    it 'keeps only the leaf container' do
      expect(hrefs).to eq(%w[/news/2024/inner-story])
    end
  end

  context 'when a deeper container appears after a shallow one' do
    let(:html) do
      <<~HTML
        <html><body>
          <article><a href="/news/2024/shallow-story">Shallow story title</a></article>
          <section><div><article><a href="/news/2024/deep-story">Deep story title</a></article></div></section>
        </body></html>
      HTML
    end

    it 'orders the deeper container first' do
      expect(hrefs).to eq(%w[/news/2024/deep-story /news/2024/shallow-story])
    end
  end

  context 'when a list item wraps an article' do
    let(:html) do
      <<~HTML
        <html><body>
          <ul><li><article><a href="/news/2024/listed-story">Listed story title</a></article></li></ul>
        </body></html>
      HTML
    end

    it 'rejects the wrapping list item' do
      expect(hrefs).to eq(%w[/news/2024/listed-story])
    end
  end

  context 'when a candidate sits inside page chrome' do
    let(:html) do
      <<~HTML
        <html><body>
          <footer><article><a href="/news/2024/footer-story">Footer story title</a></article></footer>
          <article><a href="/news/2024/main-story">Main story title</a></article>
        </body></html>
      HTML
    end

    it 'skips the chrome candidate' do
      expect(hrefs).to eq(%w[/news/2024/main-story])
    end
  end

  context 'when a container has no link' do
    let(:html) do
      <<~HTML
        <html><body><article><p>Plain paragraph without any link at all here.</p></article></body></html>
      HTML
    end

    it 'drops the container' do
      expect(segments).to be_empty
    end
  end

  context 'when one link wraps a card of several leaf divs' do
    let(:html) do
      <<~HTML
        <html><body><a class="clip" href="/play/clips/harbor-ferry-returns">
          <div class="media"><img src="/img/ferry.jpg" alt=""></div>
          <div class="title"><h3>Harbor ferry returns</h3></div>
          <div class="lead"><p>The crossing resumes after weeks of repairs.</p></div>
          <div class="note"><p>Captions are available for this clip.</p></div>
        </a></body></html>
      HTML
    end

    it 'roots one segment at the link', :aggregate_failures do
      expect(hrefs).to eq(%w[/play/clips/harbor-ferry-returns])
      expect(segments.first.root_node).to equal(segments.first.primary_link)
    end
  end

  context 'when a list item holds a whole-card link of several leaf divs' do
    let(:html) do
      <<~HTML
        <html><body><ul><li><a class="clip" href="/play/clips/harbor-ferry-returns">
          <div class="title"><h3>Harbor ferry returns</h3></div>
          <div class="lead"><p>The crossing resumes after weeks of repairs.</p></div>
          <div class="note"><p>Captions are available for this clip.</p></div>
        </a></li></ul></body></html>
      HTML
    end

    it 'keeps only the list item segment', :aggregate_failures do
      expect(hrefs).to eq(%w[/play/clips/harbor-ferry-returns])
      expect(segments.first.root_node.name).to eq(:li)
    end
  end

  context 'when a card div holds its own linked heading and an info div' do
    let(:html) do
      <<~HTML
        <html><body><div class="grid">
          <div class="item"><h3><a href="/news/2024/first-story">First story title</a></h3>
            <div class="info"><time datetime="2024-01-01">10:00</time></div></div>
          <div class="item"><h3><a href="/news/2024/second-story">Second story title</a></h3>
            <div class="info"><time datetime="2024-01-02">11:00</time></div></div>
        </div></body></html>
      HTML
    end

    it 'keeps each card as a leaf segment', :aggregate_failures do
      expect(hrefs).to eq(%w[/news/2024/first-story /news/2024/second-story])
      expect(segments.map { _1.root_node.attrs.class_names }).to all(eq(%w[item]))
    end
  end

  context 'when a div wraps a linked section heading and rows of other links' do
    let(:html) do
      <<~HTML
        <html><body><div class="section">
          <h2><a href="/news/">Latest news</a></h2>
          <div class="row"><a href="/news/2024/first-story">First story title</a></div>
          <div class="row"><a href="/news/2024/second-story">Second story title</a></div>
        </div></body></html>
      HTML
    end

    it 'does not take the section wrapper for a card', :aggregate_failures do
      expect(hrefs).to eq(%w[/news/2024/first-story /news/2024/second-story])
      expect(segments.map { _1.root_node.attrs.class_names }).to all(eq(%w[row]))
    end
  end

  context 'when a card div holds an inner div with its own heading' do
    let(:html) do
      <<~HTML
        <html><body><div class="block">
          <h3><a href="/news/2024/outer-story">Outer story title</a></h3>
          <div class="card"><h4><a href="/news/2024/inner-story">Inner story title</a></h4></div>
        </div></body></html>
      HTML
    end

    it 'keeps only the inner card', :aggregate_failures do
      expect(hrefs).to eq(%w[/news/2024/inner-story])
    end
  end
end
