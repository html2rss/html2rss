# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter::List do
  let(:hrefs_for) do
    lambda do |html, **opts|
      Html2rss::AutoSource::Segmenter.call(
        document_for(html), base_url: 'https://example.com', strategy: :list, **opts
      ).map { _1.primary_link.attrs.href }
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
  end
end
