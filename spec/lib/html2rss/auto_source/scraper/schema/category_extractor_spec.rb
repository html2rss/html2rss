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
          about: 'science, politics'
        }
      end

      it 'combines categories from both sources' do
        expect(categories).to contain_exactly('tech', 'science', 'politics')
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

  describe '.extract_field_categories' do
    subject(:categories) { described_class.extract_field_categories(schema_object) }

    context 'with array values' do
      let(:schema_object) do
        {
          keywords: %w[tech science],
          categories: %w[news politics],
          tags: %w[sports health]
        }
      end

      it 'extracts categories from all array fields' do
        expect(categories).to contain_exactly('tech', 'science', 'news', 'politics', 'sports', 'health')
      end
    end

    context 'with string values' do
      let(:schema_object) do
        {
          keywords: 'tech, science',
          categories: 'news; politics',
          tags: 'sports|health'
        }
      end

      it 'extracts categories from all string fields' do
        expect(categories).to contain_exactly('tech', 'science', 'news', 'politics', 'sports', 'health')
      end
    end

    context 'with mixed array and string values' do
      let(:schema_object) do
        {
          keywords: ['tech'],
          categories: 'science, politics',
          tags: ['sports']
        }
      end

      it 'extracts categories from all fields' do
        expect(categories).to contain_exactly('tech', 'science', 'politics', 'sports')
      end
    end

    context 'with empty arrays and strings' do
      let(:schema_object) do
        {
          keywords: [],
          categories: '',
          tags: '   ,  ,  '
        }
      end

      it 'filters out empty categories' do
        expect(categories).to be_empty
      end
    end

    context 'with non-string, non-array values' do
      let(:schema_object) do
        {
          keywords: 123,
          categories: { nested: 'value' },
          tags: true
        }
      end

      it 'ignores non-string, non-array values' do
        expect(categories).to be_empty
      end
    end
  end

  describe '.extract_about_categories' do
    subject(:categories) { described_class.extract_about_categories(schema_object) }

    context 'when about is nil' do
      let(:schema_object) { { about: nil } }

      it 'returns empty set' do
        expect(categories).to eq(Set.new)
      end
    end

    context 'when about is missing' do
      let(:schema_object) { {} }

      it 'returns empty set' do
        expect(categories).to eq(Set.new)
      end
    end

    context 'when about is an array' do
      let(:schema_object) do
        {
          about: [
            { name: 'Technology' },
            { name: 'Science' },
            'Politics',
            { other: 'value' },
            123
          ]
        }
      end

      it 'extracts categories from array items' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'when about is a string' do
      let(:schema_object) do
        {
          about: 'Technology, Science; Politics|Health'
        }
      end

      it 'extracts categories by splitting on separators' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics', 'Health')
      end
    end

    context 'when about is neither array nor string' do
      let(:schema_object) { { about: 123 } }

      it 'returns empty set' do
        expect(categories).to eq(Set.new)
      end
    end
  end

  describe '.extract_field_value' do
    subject(:categories) { described_class.extract_field_value(schema_object, field) }

    context 'when field value is an array' do
      let(:schema_object) { { keywords: ['tech', 'science', ''] } }
      let(:field) { 'keywords' }

      it 'extracts non-empty string values' do
        expect(categories).to contain_exactly('tech', 'science')
      end
    end

    context 'when field value is a string' do
      let(:schema_object) { { keywords: 'tech, science; politics' } }
      let(:field) { 'keywords' }

      it 'extracts categories by splitting on separators' do
        expect(categories).to contain_exactly('tech', 'science', 'politics')
      end
    end

    context 'when field value is nil' do
      let(:schema_object) { { keywords: nil } }
      let(:field) { 'keywords' }

      it 'returns empty set' do
        expect(categories).to eq(Set.new)
      end
    end

    context 'when field value is missing' do
      let(:schema_object) { {} }
      let(:field) { 'keywords' }

      it 'returns empty set' do
        expect(categories).to eq(Set.new)
      end
    end

    context 'when field value is neither array nor string' do
      let(:schema_object) { { keywords: 123 } }
      let(:field) { 'keywords' }

      it 'returns empty set' do
        expect(categories).to eq(Set.new)
      end
    end
  end

  describe '.extract_about_array' do
    subject(:categories) { described_class.extract_about_array(about) }

    context 'with hash items containing name' do
      let(:about) do
        [
          { name: 'Technology' },
          { name: 'Science' },
          { name: 'Politics' }
        ]
      end

      it 'extracts name values from hash items' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'with string items' do
      let(:about) { %w[Technology Science Politics] }

      it 'extracts string items directly' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'with mixed hash and string items' do
      let(:about) do
        [
          { name: 'Technology' },
          'Science',
          { name: 'Politics' },
          'Health'
        ]
      end

      it 'extracts from both hash names and strings' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics', 'Health')
      end
    end

    context 'with hash items without name' do
      let(:about) do
        [
          { name: 'Technology' },
          { other: 'value' },
          'Science'
        ]
      end

      it 'ignores hash items without name' do
        expect(categories).to contain_exactly('Technology', 'Science')
      end
    end

    context 'with non-hash, non-string items' do
      let(:about) do
        [
          { name: 'Technology' },
          123,
          'Science',
          true
        ]
      end

      it 'ignores non-hash, non-string items' do
        expect(categories).to contain_exactly('Technology', 'Science')
      end
    end
  end

  describe '.extract_string_categories' do
    subject(:categories) { described_class.extract_string_categories(string) }

    context 'with comma-separated values' do
      let(:string) { 'Technology, Science, Politics' }

      it 'splits on commas and strips whitespace' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'with semicolon-separated values' do
      let(:string) { 'Technology; Science; Politics' }

      it 'splits on semicolons and strips whitespace' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'with pipe-separated values' do
      let(:string) { 'Technology|Science|Politics' }

      it 'splits on pipes and strips whitespace' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'with mixed separators' do
      let(:string) { 'Technology, Science; Politics|Health' }

      it 'splits on all separators' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics', 'Health')
      end
    end

    context 'with extra whitespace' do
      let(:string) { '  Technology  ,  Science  ;  Politics  |  Health  ' }

      it 'strips whitespace from all values' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics', 'Health')
      end
    end

    context 'with empty values' do
      let(:string) { 'Technology, , Science, , Politics' }

      it 'filters out empty values' do
        expect(categories).to contain_exactly('Technology', 'Science', 'Politics')
      end
    end

    context 'with only separators and whitespace' do
      let(:string) { '  ,  ;  |  ' }

      it 'returns empty set' do
        expect(categories).to be_empty
      end
    end

    context 'with empty string' do
      let(:string) { '' }

      it 'returns empty set' do
        expect(categories).to be_empty
      end
    end
  end
end
