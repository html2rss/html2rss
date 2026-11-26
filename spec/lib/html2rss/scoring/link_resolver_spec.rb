# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength
RSpec.describe Html2rss::Scoring::LinkResolver do
  subject(:resolver) { described_class.new('https://example.com/articles/') }

  describe '#list_more_text?' do
    it 'names a list-level term of the page scope only, never a true read-more term', :aggregate_failures do
      vi = described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:vi])

      expect(['Xem tất cả', 'Đọc tiếp', 'Read more'].map { vi.list_more_text?(_1) }).to eq([true, false, false])
      expect(resolver.list_more_text?('Xem tất cả')).to be(false)
    end
  end

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

    it 'normalizes repeated link text once per resolver', :aggregate_failures do
      resolver = described_class.new('https://example.com/')
      texts = Array.new(2) { +"Contact us\u200F" }
      texts.each do |text|
        allow(text).to receive(:unicode_normalize).and_call_original
        resolver.utility_text?(text)
      end
      expect(texts.first).to have_received(:unicode_normalize).once
      expect(texts.last).not_to have_received(:unicode_normalize)
    end
  end

  describe '#facts_for' do
    let(:url) { Html2rss::Url.from_relative('/news/2024/launch', 'https://example.com') }

    it 'builds facts once per URL and shares them with #destination_facts', :aggregate_failures do
      facts = resolver.facts_for(url)

      expect(facts.destination).to eq('https://example.com/news/2024/launch')
      expect(resolver.facts_for(url)).to be(facts)
      expect(resolver.destination_facts('/news/2024/launch')).to be(facts)
    end
  end

  describe '#destination_facts memoization and href extraction' do
    let(:launch_href) { '/news/2024/launch' }

    it 'derives facts from a node href and returns the same object for a node seen twice', :aggregate_failures do
      node = Html2rss::Html::SST::Node.build(name: :a, attrs: Html2rss::Html::SST::Attrs.build(href: launch_href))
      facts = resolver.destination_facts(node)

      expect(facts.destination).to eq('https://example.com/news/2024/launch')
      expect(resolver.destination_facts(node)).to be(facts)
    end

    it 'shares facts between distinct nodes and plain hrefs with the same target', :aggregate_failures do
      first = Html2rss::Html::SST::Node.build(name: :a, attrs: Html2rss::Html::SST::Attrs.build(href: launch_href))
      second = Html2rss::Html::SST::Node.build(name: :a, attrs: Html2rss::Html::SST::Attrs.build(href: launch_href))
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
      expect(resolver.destination_facts(Html2rss::Html::SST::Node.build(name: :a))).to be_nil
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

  describe '#utility_chrome_text?' do
    it 'classifies short whole utility labels and calls to action, not headlines opening with a utility word',
       :aggregate_failures do
      expect(resolver.utility_chrome_text?('Contact us')).to be(true)
      expect(resolver.utility_chrome_text?('Subscribe to our newsletter')).to be(true)
      expect(resolver.utility_chrome_text?('Contact tracing app fails')).to be(false)
    end
  end

  describe '#page_only_chrome_text?' do
    it 'reads a label only a page-only language knows as chrome', :aggregate_failures do
      zh = described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:zh])
      expect(zh.page_only_chrome_text?('评论')).to be(true)
      expect(zh.page_only_chrome_text?('Contact us')).to be(false)
      expect(resolver.page_only_chrome_text?('评论')).to be(false)
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

  describe '#initialize with a page language' do
    it 'reads utility text and routes in the scope it was built with', :aggregate_failures do
      swedish = described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:sv])
      english = described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:en])

      expect(swedish.utility_text?('Dela')).to be(true)
      expect(english.utility_text?('Dela')).to be(false)
      expect(resolver.utility_text?('Dela')).to be(true)
      expect(english.destination_facts('/tema').taxonomy_path).to be(false)
      expect(swedish.destination_facts('/tema').taxonomy_path).to be(true)
      expect(described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:es])
        .destination_facts('/tema').taxonomy_path).to be(true)
    end

    it 'keeps facts per resolver, so no scope sees another scope\'s memo', :aggregate_failures do
      es = described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:es])
      en = described_class.new('https://example.com/', vocabulary: Html2rss::Vocabulary[:en])

      expect(es.destination_facts('/tema').taxonomy_path).to be(true)
      expect(en.destination_facts('/tema').taxonomy_path).to be(false)
    end
  end
end

# rubocop:enable RSpec/ExampleLength
