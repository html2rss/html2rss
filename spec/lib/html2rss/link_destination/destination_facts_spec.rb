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

    context 'with an obituary subdomain' do
      let(:url) { Html2rss::Url.from_absolute('https://obituaries.example.com/maria-keller-remembered-by-friends') }

      it 'flags the host label as junk', :aggregate_failures do
        expect(facts.high_confidence_junk_path).to be(true)
        expect(facts.high_confidence_utility_destination).to be(true)
      end
    end

    {
      'https://example.com/ニュース' => true,
      'https://example.com/記事/特集' => false,
      'https://example.com/著者/山田-太郎' => true,
      'https://example.com/訃報' => true,
      'https://example.com/ゲーム/今日のパズル' => true,
      'https://example.com/news/aktualności' => true,
      'https://example.com/kreuzworträtsel/heute-leicht' => true,
      'https://example.com/rédaction/jean-dupont' => true,
      'https://example.com/dödsannonser/maria-minns-av-vänner' => true,
      'https://example.com/författare/anna-lindström' => true,
      'https://example.com/auteur/jérôme-dupont' => true,
      'https://example.com/football/players/striker-signs-new-deal-1' => false,
      'https://example.com/football/players/jan-kowalski' => true,
      'https://example.com/opinion/contributors/why-cities-fail' => false,
      'https://example.com/opinion/contributors/jane-doe' => true,
      'https://example.com/redaktion/in-eigener-sache' => false
    }.each do |address, junk|
      it "classifies #{address} as junk=#{junk} from its percent-encoded path" do
        expect(described_class.build(Html2rss::Url.from_absolute(address)).high_confidence_junk_path).to be(junk)
      end
    end

    it 'exposes decoded NFC segments', :aggregate_failures do
      facts = described_class.build(Html2rss::Url.from_absolute('https://example.com/dödsannonser/x'))

      expect(facts.url.path_segments.first).to include('%')
      expect(facts.segments.first).to eq('dödsannonser'.unicode_normalize(:nfc))
    end
  end

  describe 'newspaper4k hand-labeled URL table' do
    # Verdict as the consumers apply it: Corroboration admits on content/strong evidence, Cleanup rejects on
    # junk or utility destination. `utility_path` alone does not reject a content-bearing path
    # (clatl `cribnotes/archives/2013/...` is an article).
    def article_verdict?(facts)
      (facts.content_path || facts.strong_post_suffix) &&
        !facts.high_confidence_junk_path && !facts.high_confidence_utility_destination
    end

    fixture = File.join(__dir__, '../../../fixtures/link_destination/newspaper4k_urls.txt')
    rows = File.readlines(fixture, chomp: true).grep_v(/\A#/).map { _1.split(' ', 2) }

    # Expected difference: the quoted `javascript:window.open(...)` row is not a parseable URL, so link
    # resolution never builds facts for it. The bare `javascript:` row parses and is a non-article.
    unbuildable, buildable = rows.partition { |_label, address| address.start_with?("'") }

    buildable.each do |label, address|
      it "labels #{address[0, 90]} as article=#{label == '1'}" do
        expect(article_verdict?(described_class.build(Html2rss::Url.from_absolute(address)))).to eq(label == '1')
      end
    end

    unbuildable.map(&:last).each do |address|
      it "refuses the unparseable link #{address[0, 40]} before facts are built" do
        expect { Html2rss::Url.from_absolute(address) }.to raise_error(Html2rss::Url::InvalidUrlError)
      end
    end
  end

  describe 'document-slug precision' do
    %w[
      games/best-new-games-of-the-year.html
      quiz/which-character-are-you-today.html
      products/best-wireless-headphones-under-100.html
      forum/viewtopic-how-to-fix-this-thing.php
      sports/nfl-scores-and-standings-this-week.html
      wiki/Some_Long_Wiki_Page_Title_Here.html
    ].each do |path|
      it "does not admit /#{path} as an article", :aggregate_failures do
        facts = described_class.build(Html2rss::Url.from_absolute("https://example.com/#{path}"))

        expect(facts.strong_post_suffix).to be(false)
        expect(facts.content_path).to be(false)
      end
    end
  end
end
