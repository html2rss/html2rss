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

  describe 'group_size' do
    let(:html) do
      <<~HTML
        <html><body>
          <section class="rail">
            <article class="teaser"><a href="/news/2024/rail-one">Rail story one title</a></article>
            <article class="teaser"><a href="/news/2024/rail-two">Rail story two title</a></article>
          </section>
          <section class="grid">
            <article class="card"><a href="/news/2024/grid-one">Grid story one title</a></article>
            <article class="card"><a href="/news/2024/grid-two">Grid story two title</a></article>
            <article class="card"><a href="/news/2024/grid-three">Grid story three title</a></article>
            <div class="card"><a href="/news/2024/odd-one">Odd one story title</a></div>
          </section>
        </body></html>
      HTML
    end

    it 'counts the cards that share a tag and class shape', :aggregate_failures do
      sizes = segments.to_h { [_1.primary_link.attrs.href.split('/').last, _1.group_size] }

      expect(sizes).to eq('rail-one' => 2, 'rail-two' => 2, 'grid-one' => 3, 'grid-two' => 3,
                          'grid-three' => 3, 'odd-one' => 1)
    end

    context 'when cards list the same classes in another order or case' do
      let(:html) do
        <<~HTML
          <html><body>
            <article class="card hot"><a href="/news/2024/one">Story one title</a></article>
            <article class="hot card"><a href="/news/2024/two">Story two title</a></article>
            <article class="Hot CARD"><a href="/news/2024/three">Story three title</a></article>
          </body></html>
        HTML
      end

      it 'counts them as one group' do
        expect(segments.map(&:group_size)).to eq([3, 3, 3])
      end
    end

    context 'when one list is split over repeated rows' do
      let(:html) do
        <<~HTML
          <html><body><div class="grid">
            <div class="row"><div class="card"><a href="/news/2024/a1">Story a1 title</a></div>
              <div class="card"><a href="/news/2024/a2">Story a2 title</a></div></div>
            <div class="row"><div class="card"><a href="/news/2024/b1">Story b1 title</a></div>
              <div class="card"><a href="/news/2024/b2">Story b2 title</a></div></div>
          </div></body></html>
        HTML
      end

      it 'counts the cards of all rows as one group' do
        expect(segments.map(&:group_size)).to eq([4, 4, 4, 4])
      end
    end

    context 'when cards of one class sit under different containers' do
      let(:html) do
        <<~HTML
          <html><body>
            <div class="latest"><div class="card"><a href="/news/2024/a1">Story a1 title</a></div>
              <div class="card"><a href="/news/2024/a2">Story a2 title</a></div></div>
            <div class="topic"><div class="card"><a href="/news/2024/b1">Story b1 title</a></div></div>
          </body></html>
        HTML
      end

      it 'keeps them in separate groups', :aggregate_failures do
        expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/news/2024/a1 /news/2024/a2 /news/2024/b1])
        expect(segments.map(&:group_size)).to eq([2, 2, 1])
      end
    end

    context 'when some cards of a group link audio or video destinations' do
      let(:html) do
        <<~HTML
          <html><body><div class="latest">
            <div class="card"><a href="/video/first-clip-today">First clip title today</a></div>
            <div class="card"><a href="/news/2024/a1">Story a1 title</a></div>
            <div class="card"><a href="/podcasts/first-episode-today">First episode title today</a></div>
            <div class="card"><a href="/news/2024/a2">Story a2 title</a></div>
            <div class="card"><a href="/news/2024/a3">Story a3 title</a></div>
          </div></body></html>
        HTML
      end

      it 'keeps the media cards out of the group and its size', :aggregate_failures do
        expect(hrefs.map { _1.split('/').last }).to eq(%w[first-clip-today a1 first-episode-today a2 a3])
        expect(segments.map(&:group_size)).to eq([1, 3, 1, 3, 3])
      end
    end

    context 'when cards of the same shape sit in an aside' do
      let(:html) do
        <<~HTML
          <html><body>
            <main>
              <article class="card"><a href="/news/2024/main-one">Main story one title</a></article>
              <article class="card"><a href="/news/2024/main-two">Main story two title</a></article>
            </main>
            <aside>
              <article class="card"><a href="/news/2024/side-one">Side story one title</a></article>
              <article class="card"><a href="/news/2024/side-two">Side story two title</a></article>
              <article class="card"><a href="/news/2024/side-three">Side story three title</a></article>
            </aside>
          </body></html>
        HTML
      end

      it 'keeps them out of the main content group', :aggregate_failures do
        sizes = segments.to_h { [_1.primary_link.attrs.href.split('/').last, _1.group_size] }

        expect(sizes).to eq('main-one' => 2, 'main-two' => 2, 'side-one' => 1, 'side-two' => 1, 'side-three' => 1)
      end
    end
  end
end
