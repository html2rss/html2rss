RSpec.describe Html2rss::Utils do
  describe '.build_absolute_url_from_relative(url, channel_url)' do
    let(:channel_url) { 'https://example.com' }

    {
      '/sprite.svg#play' => URI('https://example.com/sprite.svg#play'),
      '/search?q=term' => URI('https://example.com/search?q=term')
    }.each_pair do |url, uri|
      it do
        expect(described_class.build_absolute_url_from_relative(url, channel_url)).to eq uri
      end
    end
  end

  describe '.hash_to_xml' do
    let(:hash) { { 'data' => [{ 'title' => 'Headline', 'url' => 'https://example.com' }] } }

    it 'converts the hash to xml' do
      xml = <<~XML
        <html>
          <data>
            <datum>
              <title>Headline</title>
              <url>https://example.com</url>
            </datum>
          </data>
        </html>
      XML

      expect(described_class.hash_to_xml(hash)).to eq xml
    end
  end
end
