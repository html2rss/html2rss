# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::ListItem do
  let(:schema_object) do
    { item: { '@id': '123', name: 'Test Item', description: 'Test Description', url: 'http://example.com/foobar' } }
  end
  let(:url) { 'http://example.com' }
  let(:list_item) { described_class.new(schema_object, url:) }

  describe '#id' do
    it 'returns the id from the schema object' do
      expect(list_item.id).to eq('123')
    end

    it 'falls back to super if id is not present' do
      schema_object[:item].delete(:@id)
      expect(list_item.id).to eq '/foobar'
    end
  end

  describe '#title' do
    it 'returns the title from the schema object' do
      expect(list_item.title).to eq('Test Item')
    end

    it 'falls back to titleized url if title and super are not present' do
      schema_object[:item].delete(:name)
      expect(list_item.title).to eq('Foobar')
    end

    it 'is nil when all params absent' do
      schema_object[:item].delete(:name)
      schema_object[:item].delete(:url)
      schema_object[:item].delete(:description)

      expect(list_item.title).to be_nil
    end
  end

  describe '#description' do
    it 'returns the description from the schema object' do
      expect(list_item.description).to eq('Test Description')
    end

    it 'falls back to super if description is not present' do
      schema_object[:item].delete(:description)
      expect(list_item.description).to be_nil
    end
  end

  describe '#url' do
    it 'returns the url from the schema object' do
      expect(list_item.url.to_s).to eq('http://example.com/foobar')
    end

    it 'falls back to super if url is not present' do
      schema_object[:item].delete(:url)
      expect(list_item.url).to be_nil
    end

    it 'builds absolute url from relative url' do
      schema_object[:item][:url] = '/relative/path'
      expect(list_item.url.to_s).to eq('http://example.com/relative/path')
    end
  end
end
