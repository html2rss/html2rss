RSpec.describe Html2rss::Utils do
  describe '.build_absolute_url_from_relative(url, channel_url)' do
    let(:channel_url) { 'https://example.com' }

    {
      '/sprite.svg#play' => URI('https://example.com/sprite.svg#play'),
      '/search?q=term' => URI('https://example.com/search?q=term')
    }.each_pair do |url, uri|
      it { expect(described_class.build_absolute_url_from_relative(url, channel_url)).to eq uri }
    end
  end

  describe '.object_to_xml' do
    context 'with JSON object' do
      let(:hash) { { 'data' => [{ 'title' => 'Headline', 'url' => 'https://example.com' }] } }
      let(:xml) do
        <<~XML
          <hash>
            <data>
              <datum>
                <title>Headline</title>
                <url>https://example.com</url>
              </datum>
            </data>
          </hash>
        XML
      end

      it 'converts the hash to xml' do
        expect(described_class.object_to_xml(hash)).to eq xml
      end
    end

    context 'with JSON array' do
      let(:hash) { [{ 'title' => 'Headline', 'url' => 'https://example.com' }] }
      let(:xml) do
        <<~XML
          <objects>
            <object>
              <title>Headline</title>
              <url>https://example.com</url>
            </object>
          </objects>
        XML
      end

      it 'converts the hash to xml' do
        expect(described_class.object_to_xml(hash)).to eq xml
      end
    end
  end

  describe '.sanitize_url(url)' do
    let(:examples) do
      {
        ' ' => nil,
        ' http://example.com/ ' => 'http://example.com/',
        'http://ex.ampl/page?sc=345s#abc' => 'http://ex.ampl/page?sc=345s#abc',
        'https://example.com/sprite.svg#play' =>
          'https://example.com/sprite.svg#play',
        'mailto:bogus@void.space' => 'mailto:bogus@void.space',
        'http://übermedien.de' => 'http://xn--bermedien-p9a.de/',
        'http://www.詹姆斯.com/' => 'http://www.xn--8ws00zhy3a.com/'
      }
    end

    it 'sanitizes the url', aggregate_failures: true do
      examples.each_pair do |url, out|
        expect(described_class.sanitize_url(url)).to eq(out), url
      end
    end
  end
end
