# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::PageLinks::PlacementParams do
  describe '.names' do
    let(:names) do
      lambda do |*hrefs|
        described_class.names(hrefs.map { |href| Html2rss::Url.from_relative(href, 'https://example.com') })
      end
    end

    it 'finds a param that places the same stories in several slots', :aggregate_failures do
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=latest', '/c?pos=latest']).to eq(Set['pos'])
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=latest', '/c?pos=latest']).to be_frozen
    end

    it 'never collapses a param that sits on one path only (the id control)', :aggregate_failures do
      expect(names['/news.php?id=1', '/news.php?id=2', '/news.php?id=3', '/news.php?id=4']).to be_empty
      expect(names['/news.php?id=1', '/news.php?id=1&x=1', '/news.php?id=2', '/news.php?id=2&x=1']).to be_empty
    end

    it 'does not find a param whose paths each show one value' do
      expect(names['/a?id=1', '/b?id=2', '/c?id=3', '/d?id=4']).to be_empty
    end

    it 'needs MIN_PATHS distinct paths carrying the param', :aggregate_failures do
      expect(described_class::MIN_PATHS).to eq(3)
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=latest']).to be_empty
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=latest', '/c?pos=latest']).to eq(Set['pos'])
    end

    it 'needs MIN_REPEATED_PATHS paths under two or more values', :aggregate_failures do
      expect(described_class::MIN_REPEATED_PATHS).to eq(1)
      expect(names['/a?pos=top', '/b?pos=latest', '/c?pos=latest', '/d?pos=top']).to be_empty
    end

    it 'counts distinct paths, not stories, and accepts more than MIN_PATHS', :aggregate_failures do
      expect(names['/a?pos=top&x=1', '/a?pos=latest&x=1', '/a?pos=top&x=2', '/b?pos=top']).to be_empty
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=top', '/c?pos=top', '/d?pos=top',
                   '/e?pos=top']).to eq(Set['pos'])
    end

    it 'accepts more than MIN_REPEATED_PATHS repeated paths' do
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=top', '/b?pos=latest', '/c?pos=top']).to eq(Set['pos'])
    end

    it 'counts repeated paths, not repeated stories, against MIN_REPEATED_PATHS', :aggregate_failures do
      stub_const("#{described_class}::MIN_REPEATED_PATHS", 2)
      one_path = ['/a?pos=top&x=1', '/a?pos=latest&x=1', '/a?pos=top&x=2', '/a?pos=latest&x=2', '/b?pos=top',
                  '/c?pos=top']

      expect(names[*one_path]).to be_empty
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=top', '/b?pos=latest', '/c?pos=top']).to eq(Set['pos'])
    end

    it 'counts two values only when every other query pair is equal', :aggregate_failures do
      expect(names['/a?pos=top&page=1', '/a?pos=latest&page=2', '/b?pos=top', '/c?pos=top']).to be_empty
      expect(names['/a?pos=top&page=1', '/a?pos=latest&page=1', '/b?pos=top', '/c?pos=top']).to eq(Set['pos'])
    end

    it 'reads tracking params and param order as no difference', :aggregate_failures do
      expect(names['/a?page=1&pos=top&utm_source=x', '/a?pos=latest&page=1', '/b?pos=top', '/c?pos=top'])
        .to eq(Set['pos'])
    end

    it 'finds each placement param on its own evidence', :aggregate_failures do
      urls = ['/a?pos=top', '/a?pos=latest', '/b?pos=top', '/c?pos=top', '/a?src=x', '/a?src=y', '/b?src=x']

      expect(names[*urls]).to eq(Set['pos'])
      expect(names[*urls, '/c?src=x']).to eq(Set['pos', 'src'])
    end

    it 'treats a trailing slash as one path and another host as another', :aggregate_failures do
      expect(names['/a?pos=top', '/a/?pos=latest', '/b?pos=top', '/c?pos=top']).to eq(Set['pos'])
      expect(names['https://other.example.com/a?pos=top', '/a?pos=latest', '/b?pos=latest', '/c?pos=latest'])
        .to be_empty
    end

    it 'finds nothing on a page without queries or links', :aggregate_failures do
      expect(names['/a', '/b', '/c']).to be_empty
      expect(names[]).to be_empty
    end
  end
end
