# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::TextClassifier do
  subject(:classifier) { described_class.new }

  describe '#utility?' do
    [
      'About', 'About us', 'Contact', 'Comments', 'Comment', 'Log in', 'login', 'Member', 'Membership',
      'Premium', 'Pricing', 'Recommended for you', 'Share', 'Sign up', 'Subscribe', 'View all',
      'Über uns', 'Kontakt', 'Kommentare', 'Teilen', 'Abonnieren', 'Newsletter', 'Sobre nosotros',
      'Miembro', 'À propos', 'Partager', "S'inscrire", 'S’inscrire', ' Contact us', 'Contact us today'
    ].each do |text|
      it "matches the utility label #{text.inspect}" do
        expect(classifier.utility?(text)).to be(true)
      end
    end

    ['Read more', 'Aboutness', 'Contactless', 'Premiums', 'Abouts', 'Read About', ''].each do |text|
      it "rejects non-label text #{text.inspect}" do
        expect(classifier.utility?(text)).to be(false)
      end
    end

    it 'accepts non-string input through to_s', :aggregate_failures do
      expect(classifier.utility?(:about)).to be(true)
      expect(classifier.utility?(123)).to be(false)
    end

    it 'treats nil as an empty label', :aggregate_failures do
      expect(classifier.utility?(nil)).to be(false)
    end
  end

  describe '#utility_prefix?' do
    [
      'View all news', 'See all articles', 'Subscribe to our newsletter', 'Join the discussion',
      'Premium content', 'Plus membership', 'Alle anzeigen', 'Alle News', 'Abonnieren', 'Mitmachen',
      'Ver todos', 'Ver todo', 'Suscribirse', 'Boletín', 'Boletin', 'Voir tout', "S'abonner",
      'S’abonner', 'Rejoindre', '  View all'
    ].each do |text|
      it "matches the prefix label #{text.inspect}" do
        expect(classifier.utility_prefix?(text)).to be(true)
      end
    end

    ['Login', 'About', 'Viewer list', 'Joined today', 'Plusieurs', 'Read View all', ''].each do |text|
      it "rejects non-prefix text #{text.inspect}" do
        expect(classifier.utility_prefix?(text)).to be(false)
      end
    end

    it 'accepts non-string input through to_s', :aggregate_failures do
      expect(classifier.utility_prefix?(:subscribe)).to be(true)
      expect(classifier.utility_prefix?(nil)).to be(false)
    end
  end

  describe '#recommended?' do
    [
      'Recommended', 'Recommended for you', 'Empfohlen für dich', 'Empfohlen fuer dich',
      'Recomendado para ti', 'Recommandé pour vous', 'Recommandé', '  Recommended'
    ].each do |text|
      it "matches the recommendation label #{text.inspect}" do
        expect(classifier.recommended?(text)).to be(true)
      end
    end

    ['Not recommended', 'Recommend', 'Recommendations', 'Empfehlung', ''].each do |text|
      it "rejects non-recommendation text #{text.inspect}" do
        expect(classifier.recommended?(text)).to be(false)
      end
    end

    it 'accepts non-string input through to_s', :aggregate_failures do
      expect(classifier.recommended?(:recommended)).to be(true)
      expect(classifier.recommended?(nil)).to be(false)
    end
  end
end
