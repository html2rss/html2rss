RSpec.describe Html2rss::AttributePostProcessors::SanitizeHtml do
  subject { described_class.new(html, config: config).get }

  let(:config) do
    Html2rss::Config.new(
      channel: { title: 'Example: questions', url: 'https://example.com/questions' },
      selectors: {
        items: { selector: '#questions > ul > li' },
        title: { selector: 'a' },
        link: { selector: 'a', extractor: 'href' }
      }
    )
  end

  let(:html) do
    <<~HTML
      <html lang="en">
        <body>
          <script src="http://evil.js"></script>
          <script>alert('lol')</script>
          <marquee>Breaking news: I'm a deprecated tag</marquee>
          <iframe hidden src="http://mine.currency"></iframe>
          <div>
            <img src='/lol.gif' id="funnypic" alt="An animal looking cute">
            </html>
            <a href="http://example.com" class="link" title="foo" style="color: red">example.com</a>
            <a href="/article-123">Click here!</a>
          </div>
        </body>
      </html>
    HTML
  end

  let(:sanitzed_html) do
    [
      "Breaking news: I'm a deprecated tag ",
      '<div> ',
      '<a href="https://example.com/lol.gif" rel="nofollow noopener noreferrer" target="_blank">',
      '<img src="https://example.com/lol.gif" alt="An animal looking cute" referrer-policy="no-referrer">',
      '</a> ',
      '<a href="http://example.com" title="foo" rel="nofollow noopener noreferrer" target="_blank">',
      'example.com</a> ',
      '<a href="https://example.com/article-123" rel="nofollow noopener noreferrer" target="_blank">',
      'Click here!</a> ',
      '</div>'
    ].join
  end

  it { is_expected.to eq sanitzed_html }
end
