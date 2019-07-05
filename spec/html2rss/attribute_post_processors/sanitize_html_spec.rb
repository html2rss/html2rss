RSpec.describe Html2rss::AttributePostProcessors::SanitizeHtml do
  let(:html) {
    <<~HTML
      <script src="http://evil.js"></script>
      <script>alert('lol')</script>
      <iframe src="http://mine.currency"></iframe>
      </html>
      <a href="http://example.com">example.com</a>
    HTML
  }

  let(:sanitzed_html) {
    '<a href="http://example.com" rel="nofollow noopener noreferrer" target="_blank">example.com</a>'
  }

  subject { described_class.new(html, nil, nil).get }

  it { is_expected.to eq sanitzed_html }
end
