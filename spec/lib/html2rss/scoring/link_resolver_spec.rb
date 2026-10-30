# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength
RSpec.describe Html2rss::Scoring::LinkResolver do
  subject(:resolver) { described_class.new('https://example.com/articles/') }

  describe '#destination_facts' do
    it 'returns nil when URL normalization rejects a malformed href' do
      expect(resolver.destination_facts('http://example .com')).to be_nil
    end

    it 'keeps author routes classified as junk' do
      expect(resolver.destination_facts('/author/jane'))
        .to have_attributes(high_confidence_junk_path: true, strong_post_suffix: false)
    end

    it 'keeps archive routes classified as junk' do
      expect(resolver.destination_facts('/archive/2024'))
        .to have_attributes(high_confidence_junk_path: true, content_path: false)
    end

    it 'keeps nested taxonomy routes classified as junk', :aggregate_failures do
      facts = resolver.destination_facts('/topics/security/cloud-security-updates')

      expect(facts.taxonomy_path).to be(true)
      expect(facts.high_confidence_junk_path).to be(true)
      expect(facts.strong_post_suffix).to be(false)
    end

    it 'does not trust category routes as post context by route alone' do
      expect(resolver.destination_facts('/category/company/platform-launch-notes-for-teams'))
        .to have_attributes(strong_post_suffix: false, high_confidence_junk_path: true)
    end

    it 'does not trust privacy routes as post context by route alone' do
      expect(resolver.destination_facts('/privacy/api-announcement-for-enterprise-admins'))
        .to have_attributes(strong_post_suffix: false, high_confidence_junk_path: true)
    end

    it 'recognizes dated news routes as article-like' do
      expect(resolver.destination_facts('/news/2024/platform-launch-notes'))
        .to have_attributes(content_path: true, strong_post_suffix: true)
    end

    it 'recognizes newsroom routes as article-like' do
      expect(resolver.destination_facts('/newsroom/2026/platform-launch-notes'))
        .to have_attributes(content_path: true, strong_post_suffix: true)
    end

    context 'with German routes and text' do
      it 'classifies news, category, and utility routes', :aggregate_failures do
        expect(resolver.destination_facts('/nachrichten/2026/neuigkeiten-zum-produkt'))
          .to have_attributes(content_path: true, strong_post_suffix: true)
        expect(resolver.destination_facts('/kategorie/politik'))
          .to have_attributes(taxonomy_path: true, high_confidence_junk_path: true)
        expect(resolver.destination_facts('/agb'))
          .to have_attributes(utility_path: true, high_confidence_junk_path: true)
      end

      it 'classifies utility prefix, general utility, and recommended text', :aggregate_failures do
        expect(resolver.utility_prefix_text?('Newsletter abonnieren')).to be(true)
        expect(resolver.utility_text?('über uns')).to be(true)
        expect(resolver.recommended_text?('Empfohlen für dich')).to be(true)
      end
    end

    context 'with Spanish routes and text' do
      it 'classifies news, category, and utility routes', :aggregate_failures do
        expect(resolver.destination_facts('/noticias/2026/lanzamiento-del-producto'))
          .to have_attributes(content_path: true, strong_post_suffix: true)
        expect(resolver.destination_facts('/categoria/economia'))
          .to have_attributes(taxonomy_path: true, high_confidence_junk_path: true)
        expect(resolver.destination_facts('/privacidad'))
          .to have_attributes(utility_path: true, high_confidence_junk_path: true)
      end

      it 'classifies utility prefix, general utility, and recommended text', :aggregate_failures do
        expect(resolver.utility_prefix_text?('Suscribirse al boletín')).to be(true)
        expect(resolver.utility_text?('Contacto')).to be(true)
        expect(resolver.recommended_text?('Recomendado para ti')).to be(true)
      end
    end

    context 'with French routes and text' do
      it 'classifies news, category, and utility routes', :aggregate_failures do
        expect(resolver.destination_facts('/actualites/2026/lancement-du-produit'))
          .to have_attributes(content_path: true, strong_post_suffix: true)
        expect(resolver.destination_facts('/categorie/technologie'))
          .to have_attributes(taxonomy_path: true, high_confidence_junk_path: true)
        expect(resolver.destination_facts('/mentions-legales'))
          .to have_attributes(utility_path: true, high_confidence_junk_path: true)
      end

      it 'classifies utility prefix, general utility, and recommended text', :aggregate_failures do
        expect(resolver.utility_prefix_text?("S'abonner")).to be(true)
        expect(resolver.utility_text?('À propos')).to be(true)
        expect(resolver.recommended_text?('Recommandé pour vous')).to be(true)
      end

      it 'classifies class/ID specific path segments correctly', :aggregate_failures do
        expect(resolver.destination_facts('/teaser/my-new-post'))
          .to have_attributes(content_path: true)
        expect(resolver.destination_facts('/sidebar/some-link'))
          .to have_attributes(utility_path: true)
      end
    end
  end

  describe '#initialize' do
    it 'resolves relative hrefs against the base URL' do
      facts = described_class.new('https://example.com/articles/').destination_facts('story-slug-here')

      expect(facts.destination).to eq('https://example.com/articles/story-slug-here')
    end

    it 'exposes a text classifier that answers utility questions' do
      expect(described_class.new('https://example.com/').text_classifier.utility?('Contact us')).to be(true)
    end
  end

  describe '#destination_facts memoization and href extraction' do
    let(:launch_href) { '/news/2024/launch' }

    it 'derives facts from a node href and returns the same object for a node seen twice', :aggregate_failures do
      node = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: launch_href))
      facts = resolver.destination_facts(node)

      expect(facts.destination).to eq('https://example.com/news/2024/launch')
      expect(resolver.destination_facts(node)).to be(facts)
    end

    it 'shares facts between distinct nodes and plain hrefs with the same target', :aggregate_failures do
      first = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: launch_href))
      second = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: launch_href))
      facts = resolver.destination_facts(first)

      expect(facts).to be_a(Html2rss::LinkDestination::DestinationFacts)
      expect(resolver.destination_facts(second)).to be(facts)
      expect(resolver.destination_facts(launch_href)).to be(facts)
    end

    it 'strips surrounding whitespace from hrefs' do
      expect(resolver.destination_facts("  #{launch_href}  ").destination)
        .to eq('https://example.com/news/2024/launch')
    end

    it 'ignores fragments when resolving hrefs' do
      expect(resolver.destination_facts("#{launch_href}#comments").destination)
        .to eq('https://example.com/news/2024/launch')
    end

    it 'returns nil for nodes without an href, blank hrefs, and nil', :aggregate_failures do
      expect(resolver.destination_facts(Html2rss::SST::Node.build(name: :a))).to be_nil
      expect(resolver.destination_facts('')).to be_nil
      expect(resolver.destination_facts(nil)).to be_nil
    end
  end

  describe '#utility_text?' do
    it 'classifies general utility labels', :aggregate_failures do
      expect(resolver.utility_text?('Contact us')).to be(true)
      expect(resolver.utility_text?('Platform launch notes')).to be(false)
    end
  end

  describe '#utility_prefix_text?' do
    it 'classifies utility prefixes, not general utility labels', :aggregate_failures do
      expect(resolver.utility_prefix_text?('Subscribe to newsletter')).to be(true)
      expect(resolver.utility_prefix_text?('Contact us')).to be(false)
      expect(resolver.utility_prefix_text?('Platform launch notes')).to be(false)
    end
  end

  describe '#recommended_text?' do
    it 'classifies recommended titles', :aggregate_failures do
      expect(resolver.recommended_text?('Empfohlen für dich')).to be(true)
      expect(resolver.recommended_text?('Platform launch notes')).to be(false)
    end
  end

  describe 'token regexp constants' do
    it 'matches content-like and utility-like class/id tokens', :aggregate_failures do
      expect(described_class::CONTENT_TOKEN_REGEXP).to match('card news-item')
      expect(described_class::CONTENT_TOKEN_REGEXP).to match('post_teaser')
      expect(described_class::JUNK_TOKEN_REGEXP).to match('sidebar nav')
      expect(described_class::JUNK_TOKEN_REGEXP).to match('widget-promo')
      expect(described_class::CONTENT_TOKEN_REGEXP).not_to match('sidebar')
      expect(described_class::JUNK_TOKEN_REGEXP).not_to match('article-body')
    end
  end
end

# rubocop:enable RSpec/ExampleLength
