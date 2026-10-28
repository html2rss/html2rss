# frozen_string_literal: true

RSpec.describe Html2rss::Url do
  describe '.from_relative' do
    let(:base_url) { 'https://example.com' }

    {
      '/sprite.svg#play' => 'https://example.com/sprite.svg#play',
      '/search?q=term' => 'https://example.com/search?q=term'
    }.each_pair do |relative_url, expected_absolute|
      it "resolves #{relative_url} to #{expected_absolute}" do
        url = described_class.from_relative(relative_url, base_url)
        expect(url.to_s).to eq(expected_absolute)
      end
    end

    it 'raises ArgumentError for malformed URLs' do
      expect { described_class.from_relative('http://example .com', base_url) }
        .to raise_error(ArgumentError, 'URL could not be parsed')
    end

    it 'resolves against an already-parsed Html2rss::Url without changing the result' do
      parsed_base = described_class.from_absolute('https://example.com/section/')

      expect(described_class.from_relative('../item', parsed_base).to_s)
        .to eq(described_class.from_relative('../item', 'https://example.com/section/').to_s)
    end

    it 'strips whitespace and keeps an absolute URL instead of joining it to the base' do
      absolute = described_class.new(Addressable::URI.parse('HTTP://Example.COM/a/../b'))
      resolved = described_class.from_relative('  HTTP://Example.COM/a/../b  ', 'https://example.com/base/')

      expect(resolved).to eq(absolute)
    end

    it 'resolves a Url passed as the relative input' do
      relative = described_class.from_absolute('https://other.example/a')

      expect(described_class.from_relative(relative, 'https://example.com/base/').to_s)
        .to eq('https://other.example/a')
    end

    it 'normalizes the scheme and host of the base while joining' do
      expect(described_class.from_relative('item', 'HTTPS://Example.COM/dir/').to_s)
        .to eq('https://example.com/dir/item')
    end
  end

  describe '.sanitize' do
    {
      nil => nil,
      ' ' => nil,
      'http://example.com/ ' => 'http://example.com/',
      'http://ex.ampl/page?sc=345s#abc' => 'http://ex.ampl/page?sc=345s#abc',
      'https://example.com/sprite.svg#play' => 'https://example.com/sprite.svg#play',
      'mailto:bogus@void.space' => 'mailto:bogus@void.space',
      'http://übermedien.de' => 'http://xn--bermedien-p9a.de/',
      'http://www.詹姆斯.com/' => 'http://www.xn--8ws00zhy3a.com/',
      ',https://wurstfing.er:4711' => 'https://wurstfing.er:4711/',
      'feed:https://h2r.example.com/auto_source/aHR123' => 'https://h2r.example.com/auto_source/aHR123',
      'https://[2001:470:30:84:e276:63ff:fe72:3900]/blog/' => 'https://[2001:470:30:84:e276:63ff:fe72:3900]/blog/',
      'ftp://example.com/file' => 'ftp://example.com/file',
      'mailto://user@example.com' => 'mailto://user@example.com'
    }.each_pair do |raw_url, expected|
      it "sanitizes #{raw_url.inspect} to #{expected.inspect}" do
        result = described_class.sanitize(raw_url)
        expect(result&.to_s).to eq(expected)
      end
    end

    it 'returns a Url when the string contains an ftp URL' do
      expect(described_class.sanitize('ftp://example.com/file'))
        .to eq(described_class.from_absolute('ftp://example.com/file'))
    end
  end

  describe '.from_absolute' do
    it 'parses an absolute URL string' do
      expect(described_class.from_absolute('https://example.com/path').to_s).to eq('https://example.com/path')
    end

    it 'returns Url instances unchanged' do
      url = described_class.from_absolute('https://example.com/path')

      expect(described_class.from_absolute(url)).to equal(url)
    end

    it 'rejects relative URLs' do
      expect { described_class.from_absolute('/path') }.to raise_error(ArgumentError, 'URL must be absolute')
    end

    it 'strips surrounding whitespace' do
      expect(described_class.from_absolute('  https://example.com/a  ').to_s).to eq('https://example.com/a')
    end

    it 'normalizes scheme, host, and dot segments' do
      expect(described_class.from_absolute('HTTPS://Example.COM/a/../b').to_s).to eq('https://example.com/b')
    end

    it 'rejects an unparsable URL' do
      expect { described_class.from_absolute('http://example .com') }
        .to raise_error(ArgumentError, 'URL must be absolute')
    end

    it 'coerces non-string input with to_s' do
      expect { described_class.from_absolute(1) }.to raise_error(ArgumentError, 'URL must be absolute')
    end

    it 'returns a subclass instance unchanged' do
      child = Class.new(described_class).from_absolute('https://example.com/a')

      expect(described_class.from_absolute(child)).to equal(child)
    end
  end

  describe '#titleized' do
    {
      'http://www.example.com' => '',
      'http://www.example.com/foobar/' => 'Foobar',
      'http://www.example.com/foobar/baz.txt' => 'Foobar Baz',
      'http://www.example.com/foo-bar/baz_qux.pdf' => 'Foo Bar Baz Qux',
      'http://www.example.com/foo%20bar/baz%20qux.php' => 'Foo Bar Baz Qux',
      'http://www.example.com/foo%20bar/baz%20qux-4711.html' => 'Foo Bar Baz Qux 4711',
      'http://www.example.com/foo--bar' => 'Foo Bar'
    }.each_pair do |url_string, expected|
      it "titleizes #{url_string} to #{expected}" do
        url = described_class.from_absolute(url_string)
        expect(url.titleized).to eq(expected)
      end
    end
  end

  describe '#channel_titleized' do
    {
      'http://www.example.com' => 'www.example.com',
      'http://www.example.com/foobar' => 'www.example.com: Foobar',
      'http://www.example.com/foobar/baz' => 'www.example.com: Foobar Baz',
      'http://www.example.com/foo%20bar' => 'www.example.com: Foo bar'
    }.each_pair do |url_string, expected|
      it "channel titleizes #{url_string} to #{expected}" do
        url = described_class.from_absolute(url_string)
        expect(url.channel_titleized).to eq(expected)
      end
    end
  end

  describe '#query_values' do
    it 'returns parsed query values as a string-keyed hash' do
      url = described_class.from_absolute('https://example.com/index.php?rest_route=%2F&per_page=100')

      expect(url.query_values).to eq('rest_route' => '/', 'per_page' => '100')
    end

    it 'returns an empty hash when the url has no query string' do
      url = described_class.from_absolute('https://example.com/index.php')

      expect(url.query_values).to eq({})
    end
  end

  describe '#path_segments' do
    it 'returns normalized non-empty path segments' do
      url = described_class.from_absolute('https://example.com/wp-json/wp/v2/posts/')

      expect(url.path_segments).to eq(%w[wp-json wp v2 posts])
    end

    it 'returns an empty array for the root path' do
      url = described_class.from_absolute('https://example.com/')

      expect(url.path_segments).to eq([])
    end
  end

  describe '#with_path' do
    it 'returns a new url with the provided path' do
      url = described_class.from_absolute('https://example.com/wp-json?lang=de')

      expect(url.with_path('/wp-json/').to_s).to eq('https://example.com/wp-json/?lang=de')
    end

    it 'normalizes a replacement path' do
      url = described_class.from_absolute('https://example.com/old?x=1')

      expect(url.with_path('/a/../b')).to eq(described_class.from_absolute('https://example.com/b?x=1'))
    end

    it 'does not mutate the original url' do
      url = described_class.from_absolute('https://example.com/wp-json')

      url.with_path('/wp-json/')

      expect(url.to_s).to eq('https://example.com/wp-json')
    end
  end

  describe '#without_fragment' do
    it 'returns a copy without the fragment' do
      url = described_class.from_absolute('https://example.com/news?q=1#section')

      expect(url.without_fragment.to_s).to eq('https://example.com/news?q=1')
    end

    it 'returns self when there is no fragment' do
      url = described_class.from_absolute('https://example.com/news')

      expect(url.without_fragment).to equal(url)
    end

    it 'normalizes when dropping a fragment from an unnormalized absolute URL' do
      url = described_class.from_relative('HTTP://Example.COM/a/../b#top', 'https://example.com/')

      expect(url.without_fragment).to eq(described_class.from_absolute('http://example.com/b'))
    end

    it 'does not mutate the original url' do
      url = described_class.from_absolute('https://example.com/news#top')

      url.without_fragment

      expect(url.to_s).to eq('https://example.com/news#top')
    end
  end

  describe '#same_document?' do
    it 'matches paths that differ only by a trailing slash', :aggregate_failures do
      bare = described_class.from_absolute('https://example.com/blog')
      slash = described_class.from_absolute('https://example.com/blog/')

      expect(bare).to be_same_document(slash)
      expect(bare).not_to eq(slash)
    end

    it 'ignores fragments when comparing document identity' do
      with_fragment = described_class.from_absolute('https://example.com/blog#top')
      with_slash = described_class.from_absolute('https://example.com/blog/')

      expect(with_fragment).to be_same_document(with_slash)
    end

    it 'requires matching query strings' do
      left = described_class.from_absolute('https://example.com/a?x=1')
      right = described_class.from_absolute('https://example.com/a?x=2')

      expect(left).not_to be_same_document(right)
    end

    it 'returns false for non-Url arguments' do
      url = described_class.from_absolute('https://example.com/blog')

      expect(url.same_document?('https://example.com/blog')).to be false
    end

    it 'requires the same scheme' do
      page = described_class.from_absolute('https://example.com/blog')

      expect(page).not_to be_same_document(described_class.from_absolute('http://example.com/blog'))
    end

    it 'requires the same host' do
      page = described_class.from_absolute('https://example.com/blog')

      expect(page).not_to be_same_document(described_class.from_absolute('https://other.example/blog'))
    end

    it 'requires the same path' do
      page = described_class.from_absolute('https://example.com/blog')

      expect(page).not_to be_same_document(described_class.from_absolute('https://example.com/news'))
    end

    it 'treats a subclass instance as the same document' do
      page = described_class.from_absolute('https://example.com/blog')
      child = Class.new(described_class).from_absolute('https://example.com/blog/')

      expect(page).to be_same_document(child)
    end
  end

  describe '#with_query_values' do
    it 'returns a new url with the provided query values' do
      url = described_class.from_absolute('https://example.com/index.php?rest_route=%2F')
      updated = url.with_query_values(rest_route: '/wp/v2/posts', per_page: '100')
      expected = described_class.from_absolute('https://example.com/index.php?per_page=100&rest_route=/wp/v2/posts')

      expect(updated).to eq(expected)
    end

    it 'does not mutate the original url' do
      url = described_class.from_absolute('https://example.com/index.php?rest_route=%2F')

      url.with_query_values(rest_route: '/wp/v2/posts')

      expect(url.to_s).to eq('https://example.com/index.php?rest_route=/')
    end
  end

  describe 'delegation' do
    let(:url) { described_class.from_relative('/path', 'https://example.com') }

    it 'delegates scheme method' do
      expect(url.scheme).to eq('https')
    end

    it 'delegates host method' do
      expect(url.host).to eq('example.com')
    end

    it 'returns the registrable domain (eTLD+1)' do
      expect(described_class.from_absolute('https://www.wp.pl/').domain).to eq('wp.pl')
    end

    it 'uses the host for IP addresses instead of a public-suffix suffix' do
      expect(described_class.from_absolute('https://1.2.3.4/story').domain).to eq('1.2.3.4')
    end

    it 'delegates path method' do
      expect(url.path).to eq('/path')
    end

    it 'delegates absolute? method' do
      expect(url.absolute?).to be true
    end

    it 'exposes an explicit port' do
      expect(described_class.from_absolute('http://example.com:8080/path').port).to eq(8080)
    end

    it 'exposes the query string' do
      expect(described_class.from_absolute('https://example.com/path?q=1').query).to eq('q=1')
    end

    it 'exposes the fragment' do
      expect(described_class.from_absolute('https://example.com/path#top').fragment).to eq('top')
    end

    it 'exposes the userinfo user' do
      expect(described_class.from_absolute('https://user@example.com/a').user).to eq('user')
    end

    it 'falls back to the host when there is no registrable domain' do
      expect(described_class.from_absolute('http://localhost/x').domain).to eq('localhost')
    end
  end

  describe 'comparison' do
    let(:first_url) { described_class.from_relative('/path1', 'https://example.com') }
    let(:second_url) { described_class.from_relative('/path2', 'https://example.com') }
    let(:first_url_dup) { described_class.from_relative('/path1', 'https://example.com') }

    it 'compares equal URLs correctly' do
      expect(first_url).to eq(first_url_dup)
    end

    it 'compares different URLs correctly' do
      expect(first_url).not_to eq(second_url)
    end

    it 'compares URLs with spaceship operator for equality' do
      expect(first_url <=> first_url_dup).to eq(0)
    end

    it 'compares URLs with spaceship operator for inequality' do
      expect(first_url <=> second_url).not_to eq(0)
    end

    it 'orders URLs lexicographically by their string' do
      expect(first_url <=> second_url).to eq(-1)
    end

    it 'orders by the string form of a non-URL' do
      expect(first_url <=> 1).to eq(1)
    end

    it 'is not equal to the URL string' do
      expect(first_url).not_to eq(first_url.to_s)
    end

    it 'treats a subclass instance with the same URL as equal' do
      child = Class.new(described_class).from_absolute(first_url.to_s)

      expect(first_url).to eq(child)
    end

    it 'matches eql? when the normalized strings match' do
      expect(first_url).to eql(first_url_dup)
    end

    it 'rejects eql? for a different URL' do
      expect(first_url).not_to eql(second_url)
    end

    it 'hashes by the normalized URL string' do
      expect(first_url.hash).to eq(first_url.to_s.hash)
    end

    it 'includes the class, object id, and URI in inspect' do
      addressable = /#<Addressable::URI:0x[0-9a-f]+ URI:#{Regexp.escape(first_url.to_s)}>/
      expect(first_url.inspect).to match(/\A#<Html2rss::Url:#{first_url.object_id} @uri=#{addressable}>\z/)
    end
  end

  describe '.for_channel' do
    context 'with valid absolute URLs' do
      {
        'https://example.com' => 'https://example.com/',
        'http://example.com' => 'http://example.com/',
        'https://www.example.com/path' => 'https://www.example.com/path',
        'http://subdomain.example.com:8080/path?query=value#fragment' => 'http://subdomain.example.com:8080/path?query=value#fragment',
        'https://example.com/path with spaces' => 'https://example.com/path%20with%20spaces',
        'https://example.com/path@segment' => 'https://example.com/path@segment',
        'https://truthsocial.com/@realDonaldTrump' => 'https://truthsocial.com/@realDonaldTrump'
      }.each_pair do |input_url, expected_url|
        it "accepts #{input_url.inspect} and returns normalized URL" do
          result = described_class.for_channel(input_url)
          expect(result).to be_a(described_class)
        end

        it "normalizes #{input_url.inspect} to #{expected_url.inspect}" do
          result = described_class.for_channel(input_url)
          expect(result.to_s).to eq(expected_url)
        end
      end
    end

    context 'with invalid relative URLs' do
      [
        '/relative/path',
        'relative/path',
        './relative/path',
        '../relative/path'
      ].each do |relative_url|
        it "raises ArgumentError for relative URL #{relative_url.inspect}" do
          expect { described_class.for_channel(relative_url) }
            .to raise_error(ArgumentError, 'URL must be absolute')
        end
      end
    end

    context 'with URLs containing @ character outside the path' do
      [
        'https://user@example.com',
        'https://:secret@example.com',
        'https://example.com?param=value@test',
        'https://example.com/#frag@test'
      ].each do |url_with_at|
        it "raises ArgumentError for URL with @ character: #{url_with_at.inspect}" do
          expect { described_class.for_channel(url_with_at) }
            .to raise_error(ArgumentError, 'URL must not contain an @ character')
        end
      end
    end

    context 'with unsupported schemes' do
      [
        'ftp://example.com',
        'file:///path/to/file',
        'javascript:alert("test")',
        'data:text/plain,test'
      ].each do |unsupported_url|
        it "raises ArgumentError for unsupported scheme: #{unsupported_url.inspect}" do
          expect { described_class.for_channel(unsupported_url) }
            .to raise_error(ArgumentError, /URL scheme '[^']+' is not supported/)
        end
      end

      it 'raises ArgumentError for mailto URL (unsupported scheme)' do
        expect { described_class.for_channel('mailto:test@example.com') }
          .to raise_error(ArgumentError, "URL scheme 'mailto' is not supported")
      end
    end

    context 'with edge cases' do
      it 'returns nil for nil input' do
        expect(described_class.for_channel(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(described_class.for_channel('')).to be_nil
      end

      it 'returns nil for whitespace-only string' do
        expect(described_class.for_channel('   ')).to be_nil
      end

      it 'strips surrounding whitespace' do
        expect(described_class.for_channel('  https://example.com/a  ').to_s).to eq('https://example.com/a')
      end
    end

    context 'with malformed URLs' do
      it 'raises ArgumentError for malformed URL' do
        expect { described_class.for_channel('not-a-url') }
          .to raise_error(ArgumentError, 'URL must be absolute')
      end

      it 'raises ArgumentError for URL with only scheme' do
        expect { described_class.for_channel('https://') }
          .to raise_error(ArgumentError, 'URL must be absolute')
      end
    end
  end

  describe '.extract_from_html' do
    it 'extracts canonical link' do
      html = '<html><head><link rel="canonical" href="https://example.com/canonical"></head></html>'
      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/canonical')
    end

    it 'extracts og:url' do
      html = '<html><head><meta property="og:url" content="https://example.com/og-url"></head></html>'
      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/og-url')
    end

    it 'extracts twitter:url' do
      html = '<html><head><meta name="twitter:url" content="https://example.com/twitter-url"></head></html>'
      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/twitter-url')
    end

    it 'extracts base href' do
      html = '<html><head><base href="https://example.com/base-href"></head></html>'
      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/base-href')
    end

    it 'returns nil if no indicator matches' do
      html = '<html><head></head><body>hello</body></html>'
      expect(described_class.extract_from_html(html)).to be_nil
    end

    it 'returns nil on invalid URL extracted' do
      html = '<html><head><link rel="canonical" href="not-a-url"></head></html>'
      expect(described_class.extract_from_html(html)).to be_nil
    end

    it 'prefers a canonical link over og:url' do
      html = '<link rel="canonical" href="https://example.com/canonical">' \
             '<meta property="og:url" content="https://example.com/og-url">'
      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/canonical')
    end

    it 'skips an invalid canonical link and uses og:url' do
      html = '<link rel="canonical" href="not-a-url">' \
             '<meta property="og:url" content="https://example.com/og-url">'
      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/og-url')
    end

    it 'strips whitespace around an extracted URL' do
      html = '<html><head><link rel="canonical" href="  https://example.com/canonical  "></head></html>'

      expect(described_class.extract_from_html(html).to_s).to eq('https://example.com/canonical')
    end
  end

  describe 'immutability' do
    let(:url) { described_class.from_relative('/path', 'https://example.com') }

    it 'is frozen' do
      expect(url).to be_frozen
    end

    it 'freezes the wrapped URI' do
      uri = Addressable::URI.parse('https://example.com/a')

      described_class.new(uri)

      expect(uri).to be_frozen
    end

    it 'freezes path segments' do
      expect(url.path_segments).to be_frozen
    end
  end

  describe '#join_uri' do
    it 'resolves a relative URI and returns a Url' do
      base = described_class.from_absolute('https://example.com/dir/a')

      expect(base.join_uri(Addressable::URI.parse('../item')))
        .to eq(described_class.from_absolute('https://example.com/item'))
    end

    it 'normalizes an absolute URI joined onto the base' do
      base = described_class.from_absolute('https://example.com/dir/')

      expect(base.join_uri(Addressable::URI.parse('HTTP://Example.COM/a/../b')))
        .to eq(described_class.from_absolute('http://example.com/b'))
    end
  end
end
