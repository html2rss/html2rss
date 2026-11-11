# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonState::CandidateDetector do
  describe '.candidate_array?' do
    it 'detects an array of article-like hashes', :aggregate_failures do
      expect(described_class.candidate_array?([{ title: 'T', url: '/a' }])).to be(true)
      expect(described_class.candidate_array?({ data: { items: [{ title: 'T', url: '/a' }] } })).to be(true)
    end

    it 'rejects arrays whose hashes lack a title or a url', :aggregate_failures do
      expect(described_class.candidate_array?([{ title: 'T' }])).to be(false)
      expect(described_class.candidate_array?([{ url: '/a' }])).to be(false)
    end

    it 'detects a candidate array when any hash value in a hash qualifies' do
      document = { a: { b: 1 }, c: [{ title: 'T', url: '/a' }] }

      expect(described_class.candidate_array?(document)).to be(true)
    end

    it 'detects a candidate array nested inside another array', :aggregate_failures do
      expect(described_class.candidate_array?([[{ title: 'T', url: '/a' }]])).to be(true)
      expect(described_class.candidate_array?(['x', [{ title: 'T', url: '/a' }]])).to be(true)
    end

    it 'does not treat a single title and url hash outside an array as a candidate' do
      expect(described_class.candidate_array?({ item: { title: 'T', url: '/a' } })).to be(false)
    end

    it 'does not search menu arrays for submenu link arrays' do
      menu = [
        { title: 'World', url: '/world/', children: [{ title: 'Domestic', url: '/world/domestic/' }] },
        { title: 'Sport', url: '/sport/', children: [{ title: 'Football', url: '/sport/football/' }] }
      ]

      expect(described_class.candidate_array?({ menu: })).to be(false)
    end

    it 'returns false for scalars and hashes without candidate arrays', :aggregate_failures do
      expect(described_class.candidate_array?('x')).to be(false)
      expect(described_class.candidate_array?(nil)).to be(false)
      expect(described_class.candidate_array?({ a: 1, b: { c: 'd' } })).to be(false)
    end
  end

  describe '.traversable_candidate?' do
    it 'delegates arrays and hashes to candidate detection', :aggregate_failures do
      expect(described_class.traversable_candidate?([{ title: 'T', url: '/a' }])).to be(true)
      expect(described_class.traversable_candidate?({ items: [{ title: 'T', url: '/a' }] })).to be(true)
      expect(described_class.traversable_candidate?([{ title: 'T' }])).to be(false)
    end

    it 'returns false for scalar values', :aggregate_failures do
      expect(described_class.traversable_candidate?('x')).to be(false)
      expect(described_class.traversable_candidate?(nil)).to be(false)
    end
  end

  describe '.array_of_articles?' do
    it 'is true when any hash element has both a title and a url' do
      expect(described_class.array_of_articles?([{ title: 'T', url: '/a' }])).to be(true)
    end

    it 'skips non-hash elements when searching for an article' do
      expect(described_class.array_of_articles?(['x', { title: 'T', url: '/a' }])).to be(true)
    end

    it 'accepts Hash subclasses as entries' do
      entry = Class.new(Hash)[title: 'T', url: '/a']

      expect(described_class.array_of_articles?([entry])).to be(true)
    end

    it 'accepts entries whose title and url sit in one wrapper object', :aggregate_failures do
      expect(described_class.array_of_articles?([{ node: { title: 'T', url: '/a' } }])).to be(true)
      expect(described_class.array_of_articles?([{ data: { attributes: { title: 'T', url: '/a' } } }])).to be(true)
    end

    it 'rejects entries whose author and content objects compete for the article' do
      entry = { author: { name: 'N', url: '/authors/n' }, content: { title: 'T', url: '/a' } }

      expect(described_class.array_of_articles?([entry])).to be(false)
    end

    it 'is false unless a single element has both a title and a url', :aggregate_failures do
      expect(described_class.array_of_articles?([{ title: 'T' }, { url: '/a' }])).to be(false)
      expect(described_class.array_of_articles?([{ title: 'T' }, 'x'])).to be(false)
    end

    it 'is false for arrays without hash elements', :aggregate_failures do
      expect(described_class.array_of_articles?(%w[a b])).to be(false)
      expect(described_class.array_of_articles?([[{ title: 'T', url: '/a' }]])).to be(false)
    end

    it 'is false when most title and url hashes are menu links', :aggregate_failures do
      menu = { title: 'Imprint', url: '/imprint', target: '_self' }
      article = { title: 'T', url: '/a' }

      expect(described_class.array_of_articles?([menu, menu, article])).to be(false)
      expect(described_class.array_of_articles?([menu, { title: 'T' }, 'x'])).to be(false)
    end

    it 'is true when at most half of the title and url hashes are menu links', :aggregate_failures do
      menu = { title: 'Imprint', url: '/imprint', target: '_self' }
      article = { title: 'T', url: '/a' }

      expect(described_class.array_of_articles?([menu, article])).to be(true)
      expect(described_class.array_of_articles?([menu, article, { title: 'T' }, { url: '/b' }])).to be(true)
    end
  end

  describe '.navigation_link?' do
    it 'is true for title and url hashes carrying any link-presentation key', :aggregate_failures do
      described_class::NAVIGATION_KEYS.each do |key|
        expect(described_class.navigation_link?({ title: 'Sections', url: '/sections/', key => 'x' })).to be(true)
      end
    end

    it 'is false without link-presentation keys' do
      expect(described_class.navigation_link?({ title: 'T', url: '/a', type: 'link' })).to be(false)
    end

    it 'is false when a description or publication date marks an article', :aggregate_failures do
      expect(described_class.navigation_link?({ title: 'T', url: '/a', target: '_blank', summary: 'S' })).to be(false)
      expect(described_class.navigation_link?({ title: 'T', url: '/a', target: '_blank', date: '2024-01-01' }))
        .to be(false)
      expect(described_class.navigation_link?({ title: 'T', url: '/a', target: '_blank', posted_on: '2024-01-01' }))
        .to be(false)
    end

    it 'is false when an image marks a teaser', :aggregate_failures do
      expect(described_class.navigation_link?({ title: 'T', url: '/a', target: '_self', image: '/a.jpg' })).to be(false)
      expect(described_class.navigation_link?({ title: 'T', url: '/a', rel: 'x', thumbnailUrl: '/a.jpg' })).to be(false)
    end
  end
end
