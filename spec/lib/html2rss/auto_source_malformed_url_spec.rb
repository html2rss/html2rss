# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:articles) do
    described_class.new(response, described_class::DEFAULT_CONFIG,
                        request_session: nil, vocabulary: Html2rss::Vocabulary[nil]).articles
  end

  let(:response) do
    Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/html' },
                                           url: Html2rss::Url.from_absolute('https://example.com'))
  end
  let(:body) do
    <<~HTML
      <html><body>
        <article><h2>First valid story headline</h2><p>Teaser one.</p><a href="/news/first">Read more</a></article>
        <article><h2>Broken story headline here</h2><p>Teaser two.</p><img src="#{bad}"><a href="/news/second">Read more</a></article>
      </body></html>
    HTML
  end

  ['http://exa mple.com/x', 'http://[bad/x', 'http://a..b/x'].each do |bad_url|
    context "when one item shows an image at #{bad_url.inspect}" do
      let(:bad) { bad_url }

      it 'still builds the valid items' do
        expect(articles.map { _1.url.to_s }).to include('https://example.com/news/first', 'https://example.com/news/second')
      end
    end
  end
end
