# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::Probe do
  describe '.fold' do
    it 'downcases wire strings' do
      expect(described_class.fold('APPLICATION/LD+JSON')).to eq('application/ld+json')
    end
  end

  describe '.tag' do
    it 'returns the folded element name' do
      node = Nokogiri::HTML('<DIV></DIV>').at_css('div')

      expect(described_class.tag(node)).to eq('div')
    end
  end

  describe '.mime_base' do
    it 'strips parameters and folds MIME types' do
      expect(described_class.mime_base('Application/Atom+xml; charset=utf-8')).to eq('application/atom+xml')
    end
  end

  describe '.mime_match?' do
    it 'matches canonical MIME types regardless of case' do
      expect(described_class.mime_match?('APPLICATION/RSS+XML', 'application/rss+xml')).to be(true)
    end

    it 'matches MIME types with parameters' do
      expect(described_class.mime_match?('application/atom+xml; charset=utf-8', 'application/atom+xml')).to be(true)
    end

    it 'rejects unrelated MIME types' do
      expect(described_class.mime_match?('text/html', 'application/rss+xml')).to be(false)
    end
  end

  describe '.scripts' do
    let(:document) do
      Nokogiri::HTML(<<~HTML)
        <html>
          <head>
            <script type="text/javascript">console.log('skip')</script>
            <script type="APPLICATION/LD+JSON">{"@type":"NewsArticle"}</script>
            <script type="application/json">{"state":true}</script>
          </head>
        </html>
      HTML
    end

    it 'returns scripts whose MIME type matches case-insensitively' do
      scripts = described_class.scripts(document, described_class::APPLICATION_LD_JSON)

      expect(scripts.map { |node| node['type'] }).to eq(['APPLICATION/LD+JSON'])
    end

    it 'returns all scripts when no MIME filter is given' do
      expect(described_class.scripts(document).size).to eq(3)
    end
  end

  describe '.alternate_links' do
    let(:document) do
      Nokogiri::HTML(<<~HTML)
        <html>
          <head>
            <link rel="alternate" type="APPLICATION/JSON+OEMBED" href="/oembed.json">
            <link rel="alternate" type="application/rss+xml" href="/feed.xml">
            <link rel="canonical" href="https://example.com/">
          </head>
        </html>
      HTML
    end

    it 'filters alternate links by rel and MIME type' do
      links = described_class.alternate_links(document, rel: 'alternate',
                                                        mime: described_class::APPLICATION_JSON_OEMBED)

      expect(links.map { |node| node['href'] }).to eq(['/oembed.json'])
    end

    it 'returns all rel matches when mime is omitted' do
      links = described_class.alternate_links(document, rel: 'alternate')

      expect(links.map { |node| node['href'] }).to contain_exactly('/oembed.json', '/feed.xml')
    end
  end
end
