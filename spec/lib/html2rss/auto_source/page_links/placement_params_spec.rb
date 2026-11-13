# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::PageLinks::PlacementParams do
  describe '.names' do
    let(:names) do
      lambda do |*hrefs|
        described_class.names(hrefs.map { |href| Html2rss::Url.from_relative(href, 'https://example.com') })
      end
    end
    let(:placed) { ['/a?pos=top', '/a?pos=latest', '/b?pos=top', '/b?pos=latest', '/c?pos=top'] }

    it 'finds a param that places the same stories in several slots', :aggregate_failures do
      expect(names[*placed]).to eq(Set['pos'])
      expect(names[*placed]).to be_frozen
    end

    it 'never collapses a param that sits on one path only (the id control)', :aggregate_failures do
      expect(names['/news.php?id=1', '/news.php?id=2', '/news.php?id=3', '/news.php?id=4']).to be_empty
      expect(names['/news.php?id=1', '/news.php?id=1&x=1', '/news.php?id=2', '/news.php?id=2&x=1']).to be_empty
    end

    it 'does not find a param whose paths each show one value' do
      expect(names['/a?id=1', '/b?id=2', '/c?id=3', '/d?id=4']).to be_empty
    end

    {
      id: ['/news.php?id=1', '/news.php?id=2', '/blog.php?id=3', '/event.php?id=4'],
      page: ['/news?page=1', '/news?page=2', '/blog?page=1', '/events?page=2'],
      lang: ['/a?lang=en', '/a?lang=de', '/b?lang=en', '/c?lang=en']
    }.each do |param, hrefs|
      it "does not collapse one repeated path among paths carrying ?#{param} once" do
        expect(names[*hrefs]).to be_empty
      end
    end

    it 'does not collapse a param whose values are unique per link (article ids)', :aggregate_failures do
      expect(names['/a?id=1', '/a?id=2', '/b?id=3', '/b?id=4', '/c?id=5']).to be_empty
      expect(names['/a?pos=1', '/a?pos=2', '/b?pos=3', '/b?pos=4', '/c?pos=5']).to be_empty
    end

    it 'needs a value on MIN_SHARED_VALUE_PATHS distinct paths', :aggregate_failures do
      expect(described_class::MIN_SHARED_VALUE_PATHS).to eq(2)
      expect(names['/a?pos=1', '/a?pos=2', '/b?pos=3', '/b?pos=4', '/c?pos=1']).to eq(Set['pos'])
    end

    it 'counts a value recurring on distinct paths, not on one path twice', :aggregate_failures do
      expect(names['/a?pos=1&x=1', '/a?pos=1&x=2', '/a?pos=2&x=1', '/b?pos=1&x=1', '/b?pos=4&x=1', '/c?pos=5'])
        .to eq(Set['pos'])
      expect(names['/a?pos=1&x=1', '/a?pos=1&x=2', '/a?pos=2&x=1', '/b?pos=3&x=1', '/b?pos=4&x=1', '/c?pos=5'])
        .to be_empty
    end

    it 'counts the paths a value recurs on against MIN_SHARED_VALUE_PATHS', :aggregate_failures do
      stub_const("#{described_class}::MIN_SHARED_VALUE_PATHS", 3)
      expect(names[*placed]).to eq(Set['pos'])

      stub_const("#{described_class}::MIN_SHARED_VALUE_PATHS", 4)
      expect(names[*placed]).to be_empty
    end

    it 'needs MIN_PATHS distinct paths carrying the param', :aggregate_failures do
      expect(described_class::MIN_PATHS).to eq(3)
      expect(names['/a?pos=top', '/a?pos=latest', '/b?pos=top', '/b?pos=latest']).to be_empty
      expect(names[*placed]).to eq(Set['pos'])
    end

    it 'needs MIN_REPEATED_PATHS repeated paths', :aggregate_failures do
      expect(described_class::MIN_REPEATED_PATHS).to eq(2)
      stub_const("#{described_class}::MIN_REPEATED_PATHS", 3)

      expect(names[*placed]).to be_empty
    end

    it 'needs MIN_REPEATED_SHARE of the paths repeated, the share itself included', :aggregate_failures do
      singles = ->(count) { Array.new(count) { "/p#{_1}?pos=top" } }

      expect(described_class::MIN_REPEATED_SHARE).to eq(Rational(1, 20))
      expect(names[*placed, *singles[37]]).to eq(Set['pos'])
      expect(names[*placed, *singles[38]]).to be_empty
    end

    it 'finds the param on a front page that repeats a minority of its stories' do
      singles = Array.new(40) { "/p#{_1}?pos=top" }

      expect(names[*placed, '/c?pos=latest', *singles]).to eq(Set['pos'])
    end

    it 'counts distinct paths, not stories, and accepts more than MIN_PATHS', :aggregate_failures do
      expect(names['/a?pos=top&x=1', '/a?pos=latest&x=1', '/a?pos=top&x=2', '/b?pos=top']).to be_empty
      expect(names['/a?pos=top&x=1', '/a?pos=latest&x=1', '/b?pos=top&x=1', '/b?pos=latest&x=1', '/a?pos=top&x=2'])
        .to be_empty
      expect(names[*placed, '/c?pos=latest', '/d?pos=top', '/d?pos=latest']).to eq(Set['pos'])
    end

    it 'counts repeated paths, not repeated stories', :aggregate_failures do
      one_path = ['/a?pos=top&x=1', '/a?pos=latest&x=1', '/a?pos=top&x=2', '/a?pos=latest&x=2', '/b?pos=top',
                  '/c?pos=top']

      expect(names[*one_path]).to be_empty
      expect(names[*one_path, '/b?pos=latest']).to eq(Set['pos'])
    end

    it 'counts two values only when every other query pair is equal', :aggregate_failures do
      expect(names['/a?pos=top&page=1', '/a?pos=latest&page=2', '/b?pos=top&page=1', '/b?pos=latest&page=2',
                   '/c?pos=top']).to be_empty
      expect(names['/a?pos=top&page=1', '/a?pos=latest&page=1', '/b?pos=top&page=1', '/b?pos=latest&page=1',
                   '/c?pos=top']).to eq(Set['pos'])
    end

    it 'reads tracking params and param order as no difference' do
      expect(names['/a?page=1&pos=top&utm_source=x', '/a?pos=latest&page=1', '/b?pos=top&page=1',
                   '/b?pos=latest&page=1', '/c?pos=top']).to eq(Set['pos'])
    end

    it 'finds each placement param on its own evidence', :aggregate_failures do
      urls = [*placed, '/a?src=x', '/a?src=y', '/b?src=x']

      expect(names[*urls]).to eq(Set['pos'])
      expect(names[*urls, '/b?src=y', '/c?src=x']).to eq(Set['pos', 'src'])
    end

    it 'treats a trailing slash as one path and another host as another', :aggregate_failures do
      expect(names['/a?pos=top', '/a/?pos=latest', '/b?pos=top', '/b?pos=latest', '/c?pos=top']).to eq(Set['pos'])
      expect(names['https://other.example.com/a?pos=top', '/a?pos=latest', '/b?pos=top', '/b?pos=latest',
                   '/c?pos=top']).to be_empty
    end

    it 'finds nothing on a page without queries or links', :aggregate_failures do
      expect(names['/a', '/b', '/c']).to be_empty
      expect(names[]).to be_empty
    end
  end
end
