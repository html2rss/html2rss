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
      'https://[2001:470:30:84:e276:63ff:fe72:3900]/blog/' => 'https://[2001:470:30:84:e276:63ff:fe72:3900]/blog/'
    }.each_pair do |raw_url, expected|
      it "sanitizes #{raw_url.inspect} to #{expected.inspect}" do
        result = described_class.sanitize(raw_url)
        expect(result&.to_s).to eq(expected)
      end
    end
  end

  describe '#titleized' do
    {
      'http://www.example.com' => '',
      'http://www.example.com/foobar/' => 'Foobar',
      'http://www.example.com/foobar/baz.txt' => 'Foobar Baz',
      'http://www.example.com/foo-bar/baz_qux.pdf' => 'Foo Bar Baz Qux',
      'http://www.example.com/foo%20bar/baz%20qux.php' => 'Foo Bar Baz Qux',
      'http://www.example.com/foo%20bar/baz%20qux-4711.html' => 'Foo Bar Baz Qux 4711'
    }.each_pair do |url_string, expected|
      it "titleizes #{url_string} to #{expected}" do
        url = described_class.from_relative(url_string, 'https://example.com')
        expect(url.titleized).to eq(expected)
      end
    end
  end

  describe '#channel_titleized' do
    {
      'http://www.example.com' => 'www.example.com',
      'http://www.example.com/foobar' => 'www.example.com: Foobar',
      'http://www.example.com/foobar/baz' => 'www.example.com: Foobar Baz'
    }.each_pair do |url_string, expected|
      it "channel titleizes #{url_string} to #{expected}" do
        url = described_class.from_relative(url_string, 'https://example.com')
        expect(url.channel_titleized).to eq(expected)
      end
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

    it 'delegates path method' do
      expect(url.path).to eq('/path')
    end

    it 'delegates absolute? method' do
      expect(url.absolute?).to be true
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
  end

  describe 'immutability' do
    let(:url) { described_class.from_relative('/path', 'https://example.com') }

    it 'is frozen' do
      expect(url).to be_frozen
    end
  end
end
