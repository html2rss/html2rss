# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Scraper::Schema::CategoryExtractor do
  describe '.call' do
    subject(:categories) { described_class.call(schema_object) }

    context 'when schema object has field categories' do
      let(:schema_object) do
        {
          keywords: %w[technology science],
          categories: %w[news tech],
          tags: 'politics, sports'
        }
      end

      it 'extracts categories from all field sources' do
        expect(categories).to contain_exactly('technology', 'science', 'news', 'tech', 'politics', 'sports')
      end
    end

    context 'when schema object has articleSection' do
      let(:schema_object) { { articleSection: 'World News' } }

      it 'includes articleSection' do
        expect(categories).to contain_exactly('World News')
      end
    end

    context 'when schema object has about field with array' do
      let(:schema_object) do
        {
          about: [
            { name: 'Technology' },
            { name: 'Science' },
            'Politics'
          ]
        }
      end

      it 'extracts categories from about array' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'when schema object has about field with string' do
      let(:schema_object) do
        {
          about: 'Technology, Science; Politics|Health'
        }
      end

      it 'extracts categories from about string by splitting on separators' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics', 'Health')
      end
    end

    context 'when schema object has mixed field and about categories' do
      let(:schema_object) do
        {
          keywords: ['tech'],
          articleSection: 'Opinion',
          about: 'science, politics'
        }
      end

      it 'combines categories from both sources' do
        expect(categories).to contain_exactly('tech', 'Opinion', 'science', 'politics')
      end
    end

    context 'when schema object has empty or nil values' do
      let(:schema_object) do
        {
          keywords: [],
          categories: nil,
          tags: '',
          about: nil
        }
      end

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end

    context 'when schema object has no category fields' do
      let(:schema_object) { { title: 'Test', url: 'http://example.com' } }

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end

    context 'when schema object is empty' do
      let(:schema_object) { {} }

      it 'returns empty array' do
        expect(categories).to eq([])
      end
    end
  end
end
