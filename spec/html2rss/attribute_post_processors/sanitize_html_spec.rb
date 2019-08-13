RSpec.describe Html2rss::AttributePostProcessors::SanitizeHtml do
  subject { described_class.new(html, nil, nil).get }

  let(:html) {
    <<~HTML
      <script src="http://evil.js"></script>
      <script>alert('lol')</script>
      <iframe src="http://mine.currency"></iframe>
      <img src='http://example.com/lol.gif'>
      </html>
      <a href="http://example.com">example.com</a>
    HTML
  }

  let(:sanitzed_html) {
    [
      '<img src="http://example.com/lol.gif" referrer-policy="no-referrer">',
      '<a href="http://example.com" rel="nofollow noopener noreferrer" target="_blank">example.com</a>'
    ].join(' ')
  }

  it { is_expected.to eq sanitzed_html }
end
