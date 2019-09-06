RSpec.describe Html2rss::AttributePostProcessors::SanitizeHtml do
  subject { described_class.new(html, nil, nil).get }

  let(:html) {
    <<~HTML
      <html lang="en">
        <body>
          <script src="http://evil.js"></script>
          <script>alert('lol')</script>
          <marquee>Breaking news: I'm a deprecated tag</marquee>
          <iframe hidden src="http://mine.currency"></iframe>
          <div>
            <img src='http://example.com/lol.gif' id="funnypic" alt="An animal looking cute">
            </html>
            <a href="http://example.com" class="link" title="foo" style="color: red">example.com</a>
          </div>
        </body>
      </html>
    HTML
  }

  let(:sanitzed_html) {
    [
      "Breaking news: I'm a deprecated tag",
      '<div>',
      '<img src="http://example.com/lol.gif" alt="An animal looking cute" referrer-policy="no-referrer">',
      '<a href="http://example.com" title="foo" rel="nofollow noopener noreferrer"',
      'target="_blank">example.com</a>',
      '</div>'
    ].join(' ')
  }

  it { is_expected.to eq sanitzed_html }
end
