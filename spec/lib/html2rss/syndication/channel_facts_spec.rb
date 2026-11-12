# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::Syndication::ChannelFacts do
  describe '.from' do
    let(:rss) do
      lambda do |channel_xml|
        RSS::Parser.parse(<<~XML, false)
          <?xml version="1.0"?>
          <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
            <channel><title>T</title><link>https://example.com/</link><description>D</description>
              #{channel_xml}
            </channel>
          </rss>
        XML
      end
    end

    it 'reads the author from itunes:author, else the managingEditor name part', :aggregate_failures do
      authors = [
        '<itunes:author> Show Host </itunes:author><managingEditor>editor@example.com (Ed)</managingEditor>',
        '<itunes:author> </itunes:author><managingEditor> editor@example.com (Editor Name) </managingEditor>',
        '<managingEditor> Editor Name </managingEditor>',
        '<managingEditor>editor@example.com</managingEditor>',
        '<managingEditor>Name editor@example.com</managingEditor>',
        ''
      ].map { described_class.from(rss.call(_1)).author }

      expect(authors).to eq(['Show Host', 'Editor Name', 'Editor Name', nil, nil, nil])
    end

    it 'reads itunes:explicit values as the flag they state', :aggregate_failures do
      flags = %w[true Yes explicit false no CLEAN maybe yesno].map do |value|
        described_class.from(rss.call("<itunes:explicit> #{value} </itunes:explicit>")).explicit
      end

      expect(flags).to eq([true, true, true, false, false, false, nil, nil])
    end

    it 'keeps every subcategory of a category in document order' do
      xml = '<itunes:category text="Arts"><itunes:category text="Books"/><itunes:category text="Design"/>' \
            '</itunes:category>'

      expect(described_class.from(rss.call(xml)).categories).to eq([%w[Arts Books Design]])
    end

    it 'reads the Atom feed author name, and states nothing without one or for no feed', :aggregate_failures do
      atom = lambda do |author_xml|
        RSS::Parser.parse(<<~XML, false)
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom"><title>A</title><id>urn:example:a</id>
            <updated>2024-01-01T00:00:00Z</updated>#{author_xml}</feed>
        XML
      end

      expect(described_class.from(atom.call('<author><name>Atom Author</name></author>')).author).to eq('Atom Author')
      expect(described_class.from(atom.call(''))).to eq(described_class.new)
      expect(described_class.from(nil)).to be_nil
    end
  end

  describe '#initialize' do
    it 'drops nameless categories and blank subcategories and freezes what it keeps', :aggregate_failures do
      facts = described_class.new(author: +' Host ', categories: [[' ', 'Orphan'], [+' Arts ', ' ', nil, 'Books']])

      expect(facts.author).to eq('Host')
      expect(facts.author).to be_frozen
      expect(facts.categories).to eq([%w[Arts Books]])
      expect(facts.categories).to be_frozen
      expect(facts.categories.first).to be_frozen
      expect(facts.categories.first.first).to be_frozen
    end

    it 'leaves every fact unknown by default' do
      expect(described_class.new.to_h).to eq(author: nil, categories: [], explicit: nil)
    end

    it 'keeps the explicit flag as given' do
      expect([true, false].map { described_class.new(explicit: _1).explicit }).to eq([true, false])
    end
  end
end
# rubocop:enable RSpec/ExampleLength
