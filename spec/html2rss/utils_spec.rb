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
    let(:hash) { { 'foo' => [{ 'BAR' => :baz, boing: [1, 2, 3] }] } }

    it 'converts the hash to xml' do
      expect(described_class.hash_to_xml(hash)).to include '<BAR type="symbol">baz</BAR>'
    end
  end
end
