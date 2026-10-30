# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::DestinationFacts do
  describe '.build' do
    subject(:facts) { described_class.build(url) }

    let(:url) { Html2rss::Url.from_absolute('https://example.com/news/2026/platform-launch-notes') }

    it 'keeps the normalized url and its string form', :aggregate_failures do
      expect(facts.url).to be(url)
      expect(facts.destination).to eq('https://example.com/news/2026/platform-launch-notes')
    end

    it 'exposes the normalized path segments', :aggregate_failures do
      expect(facts.segments).to eq(%w[news 2026 platform-launch-notes])
    end

    it 'classifies an article permalink as content with a strong post suffix', :aggregate_failures do
      expect(facts.content_path).to be(true)
      expect(facts.strong_post_suffix).to be(true)
    end

    it 'keeps an article permalink out of utility and taxonomy routes', :aggregate_failures do
      expect(facts.utility_path).to be(false)
      expect(facts.taxonomy_path).to be(false)
      expect(facts.vanity_path).to be(false)
    end

    it 'keeps an article permalink out of shallow and junk routes', :aggregate_failures do
      expect(facts.shallow).to be(false)
      expect(facts.high_confidence_junk_path).to be(false)
      expect(facts.high_confidence_utility_destination).to be(false)
    end

    context 'with a commerce route under a utility segment' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/dating/singles-in-berlin-heute') }

      it 'flags utility, junk and utility destination', :aggregate_failures do
        expect(facts.content_path).to be(false)
        expect(facts.strong_post_suffix).to be(false)
        expect(facts.utility_path).to be(true)
        expect(facts.high_confidence_junk_path).to be(true)
        expect(facts.high_confidence_utility_destination).to be(true)
      end
    end

    context 'with a shallow taxonomy route' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/category/security') }

      it 'flags the taxonomy path and utility destination', :aggregate_failures do
        expect(facts.taxonomy_path).to be(true)
        expect(facts.high_confidence_junk_path).to be(true)
        expect(facts.high_confidence_utility_destination).to be(true)
        expect(facts.content_path).to be(false)
      end
    end

    context 'with a vanity route' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/join') }

      it 'flags the vanity path and shallow route', :aggregate_failures do
        expect(facts.vanity_path).to be(true)
        expect(facts.shallow).to be(true)
        expect(facts.high_confidence_utility_destination).to be(true)
      end
    end

    context 'with a root url' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/') }

      it 'reports an empty segment list as shallow and non-content', :aggregate_failures do
        expect(facts.segments).to eq([])
        expect(facts.shallow).to be(true)
        expect(facts.content_path).to be(false)
        expect(facts.destination).to eq('https://example.com/')
      end
    end
  end
end
