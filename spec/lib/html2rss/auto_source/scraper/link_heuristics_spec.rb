# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength
RSpec.describe Html2rss::AutoSource::Scraper::LinkHeuristics do
  subject(:heuristics) { described_class.new('https://example.com/articles/') }

  describe '#destination_facts' do
    it 'returns nil when URL normalization rejects a malformed href' do
      expect(heuristics.destination_facts('http://example .com')).to be_nil
    end

    it 'keeps author routes classified as junk' do
      expect(heuristics.destination_facts('/author/jane'))
        .to have_attributes(high_confidence_junk_path: true, strong_post_suffix: false)
    end

    it 'keeps archive routes classified as junk' do
      expect(heuristics.destination_facts('/archive/2024'))
        .to have_attributes(high_confidence_junk_path: true, content_path: false)
    end

    it 'keeps nested taxonomy routes classified as junk', :aggregate_failures do
      facts = heuristics.destination_facts('/topics/security/cloud-security-updates')

      expect(facts.taxonomy_path).to be(true)
      expect(facts.high_confidence_junk_path).to be(true)
      expect(facts.strong_post_suffix).to be(false)
    end

    it 'does not trust category routes as post context by route alone' do
      expect(heuristics.destination_facts('/category/company/platform-launch-notes-for-teams'))
        .to have_attributes(strong_post_suffix: false, high_confidence_junk_path: true)
    end

    it 'does not trust privacy routes as post context by route alone' do
      expect(heuristics.destination_facts('/privacy/api-announcement-for-enterprise-admins'))
        .to have_attributes(strong_post_suffix: false, high_confidence_junk_path: true)
    end

    it 'recognizes dated news routes as article-like' do
      expect(heuristics.destination_facts('/news/2024/platform-launch-notes'))
        .to have_attributes(content_path: true, strong_post_suffix: true)
    end

    it 'recognizes newsroom routes as article-like' do
      expect(heuristics.destination_facts('/newsroom/2026/platform-launch-notes'))
        .to have_attributes(content_path: true, strong_post_suffix: true)
    end

    context 'with German routes and text' do
      it 'classifies news, category, and utility routes', :aggregate_failures do
        expect(heuristics.destination_facts('/nachrichten/2026/neuigkeiten-zum-produkt'))
          .to have_attributes(content_path: true, strong_post_suffix: true)
        expect(heuristics.destination_facts('/kategorie/politik'))
          .to have_attributes(taxonomy_path: true, high_confidence_junk_path: true)
        expect(heuristics.destination_facts('/agb'))
          .to have_attributes(utility_path: true, high_confidence_junk_path: true)
      end

      it 'classifies utility prefix, general utility, and recommended text', :aggregate_failures do
        expect(heuristics.utility_prefix_text?('Newsletter abonnieren')).to be(true)
        expect(heuristics.utility_text?('über uns')).to be(true)
        expect(heuristics.recommended_text?('Empfohlen für dich')).to be(true)
      end
    end

    context 'with Spanish routes and text' do
      it 'classifies news, category, and utility routes', :aggregate_failures do
        expect(heuristics.destination_facts('/noticias/2026/lanzamiento-del-producto'))
          .to have_attributes(content_path: true, strong_post_suffix: true)
        expect(heuristics.destination_facts('/categoria/economia'))
          .to have_attributes(taxonomy_path: true, high_confidence_junk_path: true)
        expect(heuristics.destination_facts('/privacidad'))
          .to have_attributes(utility_path: true, high_confidence_junk_path: true)
      end

      it 'classifies utility prefix, general utility, and recommended text', :aggregate_failures do
        expect(heuristics.utility_prefix_text?('Suscribirse al boletín')).to be(true)
        expect(heuristics.utility_text?('Contacto')).to be(true)
        expect(heuristics.recommended_text?('Recomendado para ti')).to be(true)
      end
    end

    context 'with French routes and text' do
      it 'classifies news, category, and utility routes', :aggregate_failures do
        expect(heuristics.destination_facts('/actualites/2026/lancement-du-produit'))
          .to have_attributes(content_path: true, strong_post_suffix: true)
        expect(heuristics.destination_facts('/categorie/technologie'))
          .to have_attributes(taxonomy_path: true, high_confidence_junk_path: true)
        expect(heuristics.destination_facts('/mentions-legales'))
          .to have_attributes(utility_path: true, high_confidence_junk_path: true)
      end

      it 'classifies utility prefix, general utility, and recommended text', :aggregate_failures do
        expect(heuristics.utility_prefix_text?("S'abonner")).to be(true)
        expect(heuristics.utility_text?('À propos')).to be(true)
        expect(heuristics.recommended_text?('Recommandé pour vous')).to be(true)
      end

      it 'classifies class/ID specific path segments correctly', :aggregate_failures do
        expect(heuristics.destination_facts('/teaser/my-new-post'))
          .to have_attributes(content_path: true)
        expect(heuristics.destination_facts('/sidebar/some-link'))
          .to have_attributes(utility_path: true)
      end
    end
  end

  describe '#noise_anchor?' do
    it 'rejects taxonomy destinations so scrapers do not reimplement junk rules' do
      facts = heuristics.destination_facts('/category/security')

      expect(heuristics.noise_anchor?(text: 'Security', destination_facts: facts)).to be(true)
    end

    it 'keeps content permalinks eligible' do
      facts = heuristics.destination_facts('/news/2024/platform-launch-notes')

      expect(heuristics.noise_anchor?(text: 'Platform launch notes', destination_facts: facts)).to be(false)
    end

    it 'rejects utility-prefix labels on high-confidence utility destinations' do
      facts = heuristics.destination_facts('/login')

      expect(heuristics.noise_anchor?(text: 'Login to continue', destination_facts: facts)).to be(true)
    end

    it 'rejects icon-only anchors so SemanticHtml does not keep a parallel eligibility rule' do
      html = Nokogiri::HTML('<article><a href="/news/2024/platform-launch-notes"><img src="/i.png"></a></article>')
      anchor = html.at_css('a')
      facts = heuristics.destination_facts(anchor)

      expect(heuristics.noise_anchor?(text: '', destination_facts: facts, anchor:)).to be(true)
    end

    it 'rejects anchors nested under utility landmarks outside the content container' do
      html = Nokogiri::HTML(<<~HTML)
        <article>
          <nav><a href="/news/2024/platform-launch-notes">Related</a></nav>
          <h2><a href="/news/2024/other-story">Other story</a></h2>
        </article>
      HTML
      container = html.at_css('article')
      landmark_anchor = container.at_css('nav a')
      facts = heuristics.destination_facts(landmark_anchor)

      expect(
        heuristics.noise_anchor?(
          text: 'Related',
          destination_facts: facts,
          anchor: landmark_anchor,
          container:
        )
      ).to be(true)
    end

    it 'suppresses utility chrome text on weak destinations off the heading' do
      facts = heuristics.destination_facts('/widget-xyz-detail')

      expect(
        heuristics.noise_anchor?(text: 'Contact', destination_facts: facts, heading_anchor: false)
      ).to be(true)
    end

    it 'keeps heading-linked utility labels when the destination is not high-confidence utility' do
      facts = heuristics.destination_facts('/widget-xyz-detail')

      expect(
        heuristics.noise_anchor?(text: 'Contact', destination_facts: facts, heading_anchor: true)
      ).to be(false)
    end
  end

  describe '#assess_container' do
    it 'owns observation and hard-junk so SemanticHtml only orchestrates extraction', :aggregate_failures do
      html = Nokogiri::HTML(<<~HTML)
        <article class="recommended">
          <h2><a href="/about">Recommended for you</a></h2>
        </article>
      HTML
      container = html.at_css('article')
      anchor = container.at_css('a')
      facts = heuristics.destination_facts(anchor)

      signals = heuristics.assess_container(container, anchor, destination_facts: facts)

      expect(signals).to be_a(described_class::ContainerSignals)
      expect(signals.hard_junk?).to be(true)
      expect(signals.selected_anchor_present).to be(true)
    end
  end

  describe 'ContainerSignals' do
    subject(:signals) do
      described_class::ContainerSignals.new(
        title_word_count: 4,
        path_length: 20,
        content_path: false,
        publish_marker: false,
        descriptive_context: false,
        article_container: false,
        content_tokens: false,
        junk_tokens: false,
        utility_prefix_title: false,
        recommended_title: false,
        utility_path: false,
        strong_post_suffix: false,
        shallow: true,
        high_confidence_junk_path: true,
        high_confidence_utility_destination: false,
        selected_anchor_present: true
      )
    end

    it 'owns hard-junk rejection so SemanticHtml only orchestrates DOM facts' do
      expect(signals.hard_junk?).to be(true)
    end

    it 'keeps content articles with publish markers off the hard-junk path' do
      keep = described_class::ContainerSignals.new(
        title_word_count: 7,
        path_length: 12,
        content_path: true,
        publish_marker: true,
        descriptive_context: true,
        article_container: true,
        content_tokens: true,
        junk_tokens: false,
        utility_prefix_title: false,
        recommended_title: false,
        utility_path: false,
        strong_post_suffix: true,
        shallow: false,
        high_confidence_junk_path: false,
        high_confidence_utility_destination: false,
        selected_anchor_present: true
      )

      expect(keep.hard_junk?).to be(false)
    end
  end

  describe 'AnchorSignals' do
    it 'scores heading anchors highest so ranking weights stay local to policy' do
      score = described_class::AnchorSignals.new(
        heading_anchor: true,
        heading_text_match: false,
        meaningful_text: true,
        content_like_destination: true
      ).score

      expect(score).to eq(120)
    end
  end
end
# rubocop:enable RSpec/ExampleLength
