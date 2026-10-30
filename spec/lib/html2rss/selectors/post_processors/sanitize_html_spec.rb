# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::SanitizeHtml do
  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  describe '#call' do
    subject { described_class.new(html, context).call }

    let(:channel) do
      { title: 'Example: questions', url: 'https://example.com/questions' }
    end
    let(:context) { Html2rss::Selectors::StepEnv.new(base_url: channel[:url], step_config: {}) }

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

  describe '.call' do
    subject { described_class.call(html, 'http://example.com') }

    let(:html) { '<p>Hi <a href="/world">World!</a><script></script></p>' }
    let(:sanitized_html) do
      '<p>Hi <a href="http://example.com/world" rel="nofollow noopener noreferrer" target="_blank">World!</a></p>'
    end

    it 'returns the sanitized HTML' do
      expect(subject).to eq(sanitized_html)
    end

    it 'strips style tags and their CSS contents completely' do
      dirty = "<p>Before</p>\n<style>body { display: none; } p { color: red; }</style>\n<p>After</p>"
      expect(described_class.call(dirty, 'http://example.com')).to eq("<p>Before</p>\n\n<p>After</p>")
    end

    it 'strips inline style attributes' do
      dirty = '<p style="color: red; font-size: 20px;">Styled text</p>'
      expect(described_class.call(dirty, 'http://example.com')).to eq('<p>Styled text</p>')
    end

    it 'keeps audio and video elements and adds their safe defaults', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      dirty = '<audio controls src="/a.mp3"></audio><video src="/v.mp4"></video>'

      expect(described_class.call(dirty, 'http://example.com')).to eq(
        '<audio referrerpolicy="no-referrer" crossorigin="anonymous" preload="none"></audio>' \
        '<video referrerpolicy="no-referrer" crossorigin="anonymous" preload="none" ' \
        'playsinline="true" controls="true"></video>'
      )
    end

    it 'keeps only the allowlisted global attributes', :aggregate_failures do
      dirty = '<p dir="rtl" lang="en" title="t" alt="a" translate="no" data-x="1">x</p>'

      expect(described_class.call(dirty, 'http://example.com')).to eq(
        '<p dir="rtl" lang="en" title="t" alt="a" translate="no">x</p>'
      )
    end

    it 'keeps line breaks, collapses tabs and runs of spaces, and caps blank lines', :aggregate_failures do
      expect(described_class.call("<p>one\ntwo</p>", 'http://example.com')).to eq("<p>one\ntwo</p>")
      expect(described_class.call("<p>a\t\t b</p>", 'http://example.com')).to eq('<p>a b</p>')
      expect(described_class.call("<p>a</p>\n\n\n<p>b</p>", 'http://example.com')).to eq("<p>a</p>\n\n<p>b</p>")
    end

    it 'returns nil when only whitespace or removed content remains', :aggregate_failures do
      expect(described_class.call('   ', 'http://example.com')).to be_nil
      expect(described_class.call('<script>x</script>', 'http://example.com')).to be_nil
      expect(described_class.call('', 'http://example.com')).to be_nil
    end

    it 'returns the same result for a repeated call and a different result for another base url', :aggregate_failures do
      html = '<a href="/x">x</a>'
      expected = '<a href="http://a.example/x" rel="nofollow noopener noreferrer" target="_blank">x</a>'

      expect(described_class.call(html, 'http://a.example')).to eq(expected)
      expect(described_class.call(html, 'http://a.example')).to eq(expected)
      expect(described_class.call(html, 'http://b.example')).to include('http://b.example/x')
    end

    context 'with html being nil' do
      let(:html) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe 'VALUE_TYPE' do
    let(:context) { Html2rss::Selectors::StepEnv.new(base_url: 'http://example.com', step_config: {}) }

    it 'does not raise when value is a String' do
      expect { described_class.new('some html', context) }.not_to raise_error
    end

    it 'raises when value is not a String' do
      expect do
        described_class.new(123, context)
      end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType)
    end
  end
end
