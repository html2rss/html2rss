# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::SanitizeHtml do
  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  describe '#get' do
    subject { described_class.new(html, config:).get }

    let(:config) do
      {
        channel: { title: 'Example: questions', url: 'https://example.com/questions' },
        selectors: {
          items: { selector: '#questions > ul > li' },
          title: { selector: 'a' },
          link: { selector: 'a', extractor: 'href' }
        }
      }
    end

    let(:sanitized_html) do
      <<~HTML
        Breaking news: I'm a deprecated tag
        <div>
          <a href="https://example.com/lol.gif" rel="nofollow noopener noreferrer" target="_blank"><img src="https://example.com/lol.gif" alt="An animal looking cute" referrerpolicy="no-referrer" crossorigin="anonymous" loading="lazy" decoding="async"></a>
          <a href="http://example.com" title="foo" rel="nofollow noopener noreferrer" target="_blank">example.com</a> <a href="https://example.com/article-123" rel="nofollow noopener noreferrer" target="_blank">Click here!</a>
        </div>
      HTML
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

    it do
      result = Nokogiri::HTML.fragment(subject).to_html.chomp.gsub(/\s+/, ' ')
      expected_html = Nokogiri::HTML.fragment(sanitized_html).to_html.chomp.gsub(/\s+/, ' ')

      expect(result).to eq(expected_html)
    end
  end

  describe '.get' do
    subject { described_class.get(html, 'http://example.com') }

    let(:html) { '<p>Hi <a href="/world">World!</a><script></script></p>' }
    let(:sanitized_html) do
      '<p>Hi <a href="http://example.com/world" rel="nofollow noopener noreferrer" target="_blank">World!</a></p>'
    end

    it 'returns the sanitized HTML' do
      expect(subject).to eq(sanitized_html)
    end

    context 'with html being nil' do
      let(:html) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '.validate_args!' do
    let(:context) { { foo: :bar } }

    it 'does not raise when value is a String' do
      expect do
        described_class.validate_args!('some html', context)
      end.not_to raise_error
    end

    it 'raises when value is not a String' do
      expect do
        described_class.validate_args!(123, context)
      end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType)
    end
  end
end
