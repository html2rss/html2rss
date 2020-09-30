# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::HtmlToMarkdown do
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
          <h1>Very interesting</h1>
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

  let(:markdown) do
    [
      "# Very interesting\n Breaking news: I'm a deprecated tag \n ",
      '[![An animal looking cute](https://example.com/lol.gif)](https://example.com/lol.gif) ',
      '[example.com](http://example.com "foo") ',
      "[Click here!](https://example.com/article-123) \n"
    ].join
  end

  it { is_expected.to eq markdown }
end
