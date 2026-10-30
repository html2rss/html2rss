# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter::List do
  let(:segments_for) do
    lambda do |html, **opts|
      Html2rss::AutoSource::Segmenter.call(
        document_for(html), base_url: 'https://example.com', strategy: :list, **opts
      )
    end
  end

  let(:hrefs_for) do
    lambda do |html, **opts|
      segments_for.call(html, **opts).map { _1.primary_link.attrs.href }
    end
  end

  describe 'top group selection' do
    let(:html) do
      <<~HTML
        <html><body>
          <ul class="nav-list">
            <li><a href="/a1">Alpha story headline</a></li>
            <li><a href="/a2">Beta story headline</a></li>
          </ul>
          <section class="feed">
            <div class="card"><a href="/p1">Post one headline</a></div>
            <div class="card"><a href="/p2">Post two headline</a></div>
            <div class="card"><a href="/p3">Post three headline</a></div>
          </section>
        </body></html>
      HTML
    end

    it 'keeps only the largest group when one selector is budgeted' do
      expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
        .to eq(%w[/p1 /p2 /p3])
    end

    it 'keeps every qualifying group within the selector budget' do
      expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 2))
        .to contain_exactly('/a1', '/a2', '/p1', '/p2', '/p3')
    end

    it 'drops groups below the minimum selector frequency' do
      expect(hrefs_for.call(html, minimum_selector_frequency: 3, use_top_selectors: 2))
        .to eq(%w[/p1 /p2 /p3])
    end

    context 'when the frequency floor is one and the page holds a lone anchor' do
      let(:html) { '<html><body><div><a href="/solo">Solo story headline</a></div></body></html>' }

      it 'keeps the lone anchor' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 1, use_top_selectors: 1))
          .to eq(%w[/solo])
      end
    end

    context 'when navigation chrome holds the largest group' do
      let(:html) do
        <<~HTML
          <html><body>
            <nav>
              <ul>
                <li><a href="/n1">Nav one headline</a></li>
                <li><a href="/n2">Nav two headline</a></li>
                <li><a href="/n3">Nav three headline</a></li>
              </ul>
            </nav>
            <section class="feed">
              <div class="card"><a href="/p1">Post one headline</a></div>
              <div class="card"><a href="/p2">Post two headline</a></div>
            </section>
          </body></html>
        HTML
      end

      it 'excludes navigation chrome from the candidate groups' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2])
      end
    end
  end

  describe 'card boundaries' do
    context 'when each card wraps its anchor in a span with a lead paragraph' do
      let(:html) do
        <<~HTML
          <html><body>
            <section class="feed">
              <div class="card"><span><a href="/p1">Post one headline</a></span><p>Lead one</p></div>
              <div class="card"><span><a href="/p2">Post two headline</a></span><p>Lead two</p></div>
            </section>
          </body></html>
        HTML
      end

      it 'uses each card as the segment root' do
        segments = segments_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1)

        expect(segments.map { _1.root_node.name }).to eq(%i[div div])
      end
    end

    context 'when a card holds two relevant anchors' do
      let(:html) do
        <<~HTML
          <html><body>
            <section class="feed">
              <div class="card"><p><a href="/a1">First story headline</a><a href="/a2">Second story headline</a></p></div>
              <div class="card"><p><a href="/b1">Third story headline</a><a href="/b2">Fourth story headline</a></p></div>
            </section>
          </body></html>
        HTML
      end

      it 'splits the card into one segment per anchor' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/a1 /a2])
      end
    end

    context 'when each list item wraps its anchor in a span' do
      let(:html) do
        <<~HTML
          <html><body>
            <ul class="posts">
              <li><span><a href="/p1">Post one headline</a></span></li>
              <li><span><a href="/p2">Post two headline</a></span></li>
              <li><span><a href="/p3">Post three headline</a></span></li>
            </ul>
          </body></html>
        HTML
      end

      it 'walks past the single-link wrapper up to the shared list parent' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2 /p3])
      end
    end
  end

  describe 'main landmark scoping' do
    let(:html) do
      <<~HTML
        <html><body>
          <div class="promo">
            <ul>
              <li><a href="/n1">Promo one headline</a></li>
              <li><a href="/n2">Promo two headline</a></li>
              <li><a href="/n3">Promo three headline</a></li>
            </ul>
          </div>
          <main>
            <div class="card"><a href="/m1">Main one headline</a></div>
            <div class="card"><a href="/m2">Main two headline</a></div>
          </main>
        </body></html>
      HTML
    end

    it 'ignores larger groups that sit outside main' do
      expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
        .to eq(%w[/m1 /m2])
    end

    it 'treats role=main as the main landmark' do
      role_html = html.sub('<main>', '<div role="main">').sub('</main>', '</div>')

      expect(hrefs_for.call(role_html, minimum_selector_frequency: 2, use_top_selectors: 1))
        .to eq(%w[/m1 /m2])
    end

    context 'when another role value marks a navigation region' do
      let(:html) do
        <<~HTML
          <html><body>
            <div role="navigation">
              <ul>
                <li><a href="/n1">Nav one headline</a></li>
                <li><a href="/n2">Nav two headline</a></li>
              </ul>
            </div>
            <section class="feed">
              <div class="card"><a href="/p1">Post one headline</a></div>
              <div class="card"><a href="/p2">Post two headline</a></div>
              <div class="card"><a href="/p3">Post three headline</a></div>
            </section>
          </body></html>
        HTML
      end

      it 'does not treat it as the main landmark' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2 /p3])
      end
    end

    context 'when the main landmark is an anchor itself' do
      let(:html) do
        <<~HTML
          <html><body>
            <ul class="posts">
              <li><a role="main" href="/m1">Main one headline</a></li>
              <li><a href="/m2">Other two headline</a></li>
            </ul>
          </body></html>
        HTML
      end

      it 'keeps that anchor' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 1, use_top_selectors: 1))
          .to eq(%w[/m1])
      end
    end
  end

  describe 'anchor relevance' do
    let(:html) do
      <<~HTML
        <html><body>
          <section class="feed">
            <div class="card"><a href="javascript:void(0)">Script one headline</a></div>
            <div class="card"><a href="javascript:void(0)">Script two headline</a></div>
            <div class="card"><a href="javascript:void(0)">Script three headline</a></div>
          </section>
          <section class="news">
            <div class="card"><a href="/r1">Real one headline</a></div>
            <div class="card"><a href="/r2">Real two headline</a></div>
          </section>
        </body></html>
      HTML
    end

    it 'skips anchors without a resolvable destination' do
      expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
        .to eq(%w[/r1 /r2])
    end

    context 'when taxonomy and utility anchors sit inside the cards' do
      let(:html) do
        <<~HTML
          <html><body>
            <ul class="posts">
              <li><a href="/p1">Post one headline</a><a href="/tags/ruby">Ruby</a></li>
              <li><a href="/p2">Post two headline</a><a href="/tags/rails">Rails</a></li>
              <li><a href="/p3">Post three headline</a><a href="/subscribe">Subscribe</a></li>
            </ul>
          </body></html>
        HTML
      end

      it 'drops them so they neither join nor shape the cards' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2 /p3])
      end
    end

    context 'when a taxonomy-only link group sits beside the posts' do
      let(:html) do
        <<~HTML
          <html><body>
            <div class="tags">
              <a href="/tags/ruby">Ruby</a>
              <a href="/tags/rails">Rails</a>
              <a href="/tags/web">Web</a>
            </div>
            <section class="feed">
              <div class="card"><a href="/p1">Post one headline</a></div>
              <div class="card"><a href="/p2">Post two headline</a></div>
            </section>
          </body></html>
        HTML
      end

      it 'does not let it win the top selector' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2])
      end
    end

    context 'when script links sit beside each headline' do
      let(:html) do
        <<~HTML
          <html><body>
            <ul class="posts">
              <li><a href="/p1">Post one headline</a><a href="javascript:void(0)">Menu</a></li>
              <li><a href="/p2">Post two headline</a><a href="javascript:void(0)">Menu</a></li>
              <li><a href="/p3">Post three headline</a><a href="javascript:void(0)">Menu</a></li>
            </ul>
          </body></html>
        HTML
      end

      it 'does not count them as card content' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2 /p3])
      end
    end

    context 'when icon-only anchors sit beside the headlines' do
      let(:html) do
        <<~HTML
          <html><body>
            <section class="feed">
              <div class="card"><a href="/i1"><img src="/i1.png" alt=""></a><a href="/p1">Post one headline</a></div>
              <div class="card"><a href="/i2"><img src="/i2.png" alt=""></a><a href="/p2">Post two headline</a></div>
            </section>
          </body></html>
        HTML
      end

      it 'drops the icon-only anchors from card groups' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2])
      end
    end

    context 'when a broken destination forms the larger group' do
      let(:html) do
        <<~HTML
          <html><body>
            <section class="broken">
              <div class="card"><a href="https://exa mple.com/bad-1">Broken one headline</a></div>
              <div class="card"><a href="https://exa mple.com/bad-2">Broken two headline</a></div>
              <div class="card"><a href="https://exa mple.com/bad-3">Broken three headline</a></div>
            </section>
            <section class="feed">
              <div class="card"><a href="/p1">Post one headline</a></div>
              <div class="card"><a href="/p2">Post two headline</a></div>
            </section>
          </body></html>
        HTML
      end

      it 'skips anchors whose destination cannot be resolved' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2])
      end
    end

    context 'when a utility label group is larger than the posts' do
      let(:html) do
        <<~HTML
          <html><body>
            <section class="team">
              <div class="card"><a href="/team/alice">About</a></div>
              <div class="card"><a href="/team/bob">About</a></div>
              <div class="card"><a href="/team/carol">About</a></div>
            </section>
            <section class="feed">
              <div class="card"><a href="/p1">Post one headline</a></div>
              <div class="card"><a href="/p2">Post two headline</a></div>
            </section>
          </body></html>
        HTML
      end

      it 'applies utility label filtering to the anchor text' do
        expect(hrefs_for.call(html, minimum_selector_frequency: 2, use_top_selectors: 1))
          .to eq(%w[/p1 /p2])
      end
    end
  end
end
