# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::TextClassifier do
  subject(:classifier) { described_class.new }

  describe '#utility?' do
    [
      'About', 'About us', 'Contact', 'Comments', 'Comment', 'Log in', 'login', 'Member', 'Membership',
      'Premium', 'Pricing', 'Recommended for you', 'Share', 'Sign up', 'Subscribe', 'View all',
      'Über uns', 'Kontakt', 'Kommentare', 'Teilen', 'Abonnieren', 'Newsletter', 'Sobre nosotros',
      'Miembro', 'À propos', 'Partager', "S'inscrire", 'S’inscrire', ' Contact us', 'Contact us today',
      'Chi siamo', 'Condividi', 'Over ons', 'Inloggen', 'O nas', 'Zaloguj się', 'Om oss', 'Logga in',
      'お問い合わせ', 'ログイン'
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
      'S’abonner', 'Rejoindre', '  View all', 'Vedi tutto', 'Bekijk alles', 'Zobacz wszystko', 'Visa alla',
      'すべて見る'
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
      'Recomendado para ti', 'Recommandé pour vous', 'Recommandé', '  Recommended',
      'Consigliato per te', 'Aanbevolen voor jou', 'Polecane dla ciebie', 'Rekommenderat för dig', 'おすすめ'
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

  describe '#read_more?' do
    [
      'Read more', 'Continue reading »', 'Learn more', 'More about «Harbor ferry»',
      'More about „Hafen“', 'Mehr über "Hafen"', "More about 'Harbor'", 'More about “Harbor”', 'Mehr über 「港」',
      'Weiterlesen', 'Mehr zu «Hafen»', 'MEHR ÜBER «Hafen»', 'Lire la suite', 'En savoir plus sur «Port»',
      'Leer más', 'Más sobre «Puerto»', 'Leggi tutto', 'Altro su «Porto»', 'Lees meer', 'Meer over «Haven»',
      'Czytaj więcej', 'Więcej o «Porcie»', 'Läs mer', 'Mer om «Hamnen»', '続きを読む', '「港」の続きを読む',
      '港について詳しく', "Leggi l'articolo", "  \u2192 Read more  "
    ].each do |text|
      it "matches the read-more label #{text.inspect}" do
        expect(classifier.read_more?(text)).to be(true)
      end
    end

    it 'reads decomposed accents', :aggregate_failures do
      expect(classifier.read_more?("Leer ma\u0301s".unicode_normalize(:nfd))).to be(true)
    end

    [
      'PDF', 'Der Hafen wächst', 'Mehr Lohn für alle',
      'More about the budget fight is expected tomorrow in the council', 'Reading list', 'Plus', ''
    ].each do |text|
      it "rejects non-label text #{text.inspect}" do
        expect(classifier.read_more?(text)).to be(false)
      end
    end

    it 'treats nil as an empty label', :aggregate_failures do
      expect(classifier.read_more?(nil)).to be(false)
    end
  end
end
