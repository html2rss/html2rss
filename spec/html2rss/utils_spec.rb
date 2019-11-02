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

  describe '.hash_to_xml' do
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
        expect(described_class.hash_to_xml(hash)).to eq xml
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
        expect(described_class.hash_to_xml(hash)).to eq xml
      end
    end
  end
end
