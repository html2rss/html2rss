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

    it 'detects a candidate array nested inside another array' do
      expect(described_class.candidate_array?([[{ title: 'T', url: '/a' }]])).to be(true)
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

    it 'is false unless a single element has both a title and a url', :aggregate_failures do
      expect(described_class.array_of_articles?([{ title: 'T' }, { url: '/a' }])).to be(false)
      expect(described_class.array_of_articles?([{ title: 'T' }, 'x'])).to be(false)
    end

    it 'is false for arrays without hash elements' do
      expect(described_class.array_of_articles?(%w[a b])).to be(false)
    end
  end

  describe '.title_from' do
    it 'reads title-like keys, including nested attributes', :aggregate_failures do
      expect(described_class.title_from({ title: 'T' })).to eq('T')
      expect(described_class.title_from({ name: 'N' })).to eq('N')
      expect(described_class.title_from({ attributes: { headline: 'H' } })).to eq('H')
    end

    it 'returns nil when no title-like key exists' do
      expect(described_class.title_from({ url: '/a' })).to be_nil
    end
  end

  describe '.url_from' do
    it 'reads url-like keys' do
      expect(described_class.url_from({ url: '/a' })).to eq('/a')
    end

    it 'falls back to url-like keys inside links' do
      expect(described_class.url_from({ links: { href: '/b' } })).to eq('/b')
    end

    it 'returns nil when no url-like value exists' do
      expect(described_class.url_from({ title: 'x' })).to be_nil
    end
  end
end
