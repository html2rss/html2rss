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
end
# rubocop:enable RSpec/ExampleLength
