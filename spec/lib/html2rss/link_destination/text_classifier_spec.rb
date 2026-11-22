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

  describe '#utility_chrome?' do
    [
      'Contact', 'Contact us', 'About us', 'Subscribe now', 'Share this', 'Comments (12)', 'Login »', '[Subscribe]',
      '(view all)', 'Über uns', 'ログイン', '→ Contact ←', 'Recommended for you', 'Subscribe to our newsletter',
      'Share this article with friends', 'Share this story now', 'Subscribe', 'Log in to leave a comment',
      'Contact us for more information', 'Join our community of readers', 'Sign up for the weekly digest',
      '  Subscribe to updates', 'Abonnieren Sie unseren Newsletter', 'Mitglied werden und profitieren',
      'Kommentare zum Artikel', "Abonnez-vous à notre lettre d'information", 'Abonnez vous à notre lettre',
      "S'abonner à la lettre", 'S’abonner à la lettre', 'Contactez-nous pour plus d’informations',
      'Suscríbete a nuestro boletín', 'Suscribete a nuestro boletin', 'Compartir este artículo con amigos',
      'Iniciar sesión para comentar', 'Iscriviti alla newsletter', 'Iscriviti a Esempio',
      'Condividi questo articolo', "Condividi l'articolo con gli amici", 'Unisciti alla nostra community',
      'Abonneer je op onze nieuwsbrief', 'Deel dit artikel met vrienden', 'Log in om te reageren',
      'Zapisz się do newslettera', 'Zapisz sie do newslettera', 'Zaloguj się, aby dodać komentarz',
      'Udostępnij ten artykuł znajomym', 'Dołącz do naszej społeczności', 'Prenumerera på vårt nyhetsbrev',
      'Prenumerera pa vart nyhetsbrev', 'Dela den här artikeln med vänner', 'Logga in för att kommentera',
      'Kontakta oss för mer information', 'ニュースレターを購読する', 'コメントを投稿するにはログイン', 'ログインしてコメントを書く', 'お問い合わせはこちらから',
      'Assine a nossa newsletter', 'Inscreva-se na newsletter', 'Compartilhe este artigo com amigos',
      'Faça login para comentar', 'Faca login para comentar', 'Junte-se à nossa comunidade',
      'Subscribe now to get updates', 'Log in or register to comment', 'Iscriviti ora alla nostra newsletter',
      'Kommentare zum Artikel', 'Artikel teilen', 'Mitglied werden', 'Jetzt anmelden', "S'abonner à notre newsletter",
      'Gå med i vår community', 'Compartir este artículo', 'Iniciar sesión para comentar',
      'ニュースレターを購読', 'コメントを投稿します', 'お問い合わせはこちら', '会員登録はこちら。'
    ].each do |text|
      it "matches the utility chrome #{text.inspect}" do
        expect(classifier.utility_chrome?(text)).to be(true)
      end
    end

    [
      'Contact tracing app fails', 'Join the debate on tax', 'Plus de 100 morts', 'Aboutness', 'Read more', '',
      '(12)', 'Share prices fall', 'Plus Size Fashion Week', 'Subscribers rise again', 'Shared this week',
      'Contact usage grows', 'Sign upgrades', 'Read: Subscribe to our newsletter', 'Kommentare zum Urteil',
      'Mitglied werdender Verein', 'Logging in to leave a comment', 'Iscrivitions', 'Prenumeration på tidningen',
      'ログインの手順', 'Kommentare zum Artikel 13: Was Urheber wissen müssen', 'Kommentare zum Artikel 5 Grundgesetz',
      'Artikel teilen Meinungen: Reaktionen', "S'abonner à Netflix coûte plus cher", 'Gå med i Nato kan kosta Sverige',
      'コメントを投稿した男性を逮捕', 'コメントを投稿した女性が死亡', 'ニュースレターを購読者に配信',
      'この記事をシェアした投稿が拡散', 'メルマガに登録した人に当選', 'お問い合わせはこちらで受付開始'
    ].each do |text|
      it "rejects the text #{text.inspect}" do
        expect(classifier.utility_chrome?(text)).to be(false)
      end
    end

    it 'reads an ambiguous term only in its own language scope', :aggregate_failures do
      sv = described_class.new(vocabulary: Html2rss::Vocabulary[:sv])
      en = described_class.new(vocabulary: Html2rss::Vocabulary[:en])

      expect(sv.utility_chrome?('Dela Cruz')).to be(true)
      expect(en.utility_chrome?('Dela Cruz')).to be(false)
    end

    it 'reads decomposed accents and treats nil as empty', :aggregate_failures do
      expect(classifier.utility_chrome?("U\u0308ber uns")).to be(true)
      expect(classifier.utility_chrome?(nil)).to be(false)
    end

    it 'reads decomposed accents, non-string input and nil', :aggregate_failures do
      expect(classifier.utility_chrome?("Suscri\u0301bete a nuestro boletin")).to be(true)
      expect(classifier.utility_chrome?(:'subscribe to')).to be(true)
      expect(classifier.utility_chrome?(nil)).to be(false)
    end

    it 'reads every language whatever the page language', :aggregate_failures do
      en = described_class.new(vocabulary: Html2rss::Vocabulary[:en])

      expect(en.utility_chrome?('Abonnieren Sie unseren Newsletter')).to be(true)
      expect(en.utility_chrome?('ニュースレターを購読する')).to be(true)
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
      'Find out more', 'Read full story', 'Lesen Sie mehr …', 'Mehr zum Thema', 'Mehr zum Thema «Rente»',
      'Meer informatie', 'Más información', 'Maggiori informazioni', 'Więcej informacji', 'Mer information',
      'Pour en savoir plus', 'Zobacz więcej', '詳細はこちら', 'Weiterlesen',
      'Mehr zu «Hafen»', 'MEHR ÜBER «Hafen»', 'Lire la suite', 'En savoir plus sur «Port»',
      'Leer más', 'Más sobre «Puerto»', 'Leggi tutto', 'Altro su «Porto»', 'Lees meer', 'Meer over «Haven»',
      'Czytaj więcej', 'Więcej o «Porcie»', 'Läs mer', 'Mer om «Hamnen»', '続きを読む', '「港」の続きを読む',
      '港について詳しく', "Leggi l'articolo", "  \u2192 Read more  "
    ].each do |text|
      it "matches the read-more label #{text.inspect}" do
        expect(classifier.read_more?(text)).to be(true)
      end
    end

    it 'reads decomposed accents in every label kind', :aggregate_failures do
      expect(classifier.read_more?("Leer ma\u0301s")).to be(true)
      expect(classifier.utility?("U\u0308ber uns")).to be(true)
      expect(classifier.recommended?("Recommande\u0301 pour vous")).to be(true)
      expect(classifier.utility?("A\u0300 propos")).to be(true)
    end

    [
      'PDF', 'Der Hafen wächst', 'Mehr Lohn für alle',
      'More about the budget fight is expected tomorrow in the council', 'Reading list', 'Plus',
      'Mehr zum Thema Rente', ''
    ].each do |text|
      it "rejects non-label text #{text.inspect}" do
        expect(classifier.read_more?(text)).to be(false)
      end
    end

    it 'treats nil as an empty label', :aggregate_failures do
      expect(classifier.read_more?(nil)).to be(false)
    end
  end

  describe 'new-window notices' do
    [
      '(opens in new window)', '(opens in a new tab)', '(öffnet in neuem Fenster)', '(öffnet in neuem Tab)',
      '(öffnet sich in einem neuen Fenster)', '(öffnet sich in einem neuen Tab)',
      '(ouvre dans une nouvelle fenêtre)', '(se abre en una nueva ventana)', '(si apre in una nuova finestra)',
      '(opent in nieuw venster)', '(otwiera się w nowym oknie)', '(öppnas i nytt fönster)', '（新しいウィンドウで開く）'
    ].each do |notice|
      it "ignores the trailing notice #{notice.inspect}", :aggregate_failures do
        expect(classifier.read_more?("Meer informatie #{notice}")).to be(true)
        expect(classifier.utility?("Contact #{notice}")).to be(true)
        expect(classifier.recommended?("Recommended #{notice}")).to be(true)
      end
    end

    it 'keeps a headline that only mentions a window', :aggregate_failures do
      expect(classifier.read_more?('Opens in new window as the museum reopens')).to be(false)
      expect(classifier.read_more?('(opens in new window)')).to be(false)
    end
  end

  describe 'memoization' do
    let(:first) { +'Read more (opens in new tab)' }
    let(:second) { first.dup }

    before { [first, second].each { |text| allow(text).to receive(:unicode_normalize).and_call_original } }

    it 'normalizes repeated equal text once when opted in', :aggregate_failures do
      memoized = described_class.new(memoize: true)

      expect(Array.new(3) { memoized.read_more?(first) }).to all(be(true))
      expect(memoized.utility?(second)).to be(false)
      expect(first).to have_received(:unicode_normalize).once
      expect(second).not_to have_received(:unicode_normalize)
    end

    it 'retains nothing by default, as the shared constants are built', :aggregate_failures do
      shared = described_class.new

      [first, second].each { |text| shared.read_more?(text) }
      expect(first).to have_received(:unicode_normalize).once
      expect(second).to have_received(:unicode_normalize).once
    end

    it 'keys on the string value, so mutating a caller string cannot alias an entry', :aggregate_failures do
      memoized = described_class.new(memoize: true)
      text = +'Read more'

      expect(memoized.read_more?(text)).to be(true)
      expect(memoized.read_more?(text.replace('Quarterly results'))).to be(false)
    end

    it 'treats nil as an empty label and does not cache a raising normalization', :aggregate_failures do
      memoized = described_class.new(memoize: true)
      allow(first).to receive(:unicode_normalize).and_raise(Encoding::CompatibilityError)

      expect(memoized.utility?(nil)).to be(false)
      expect { 2.times { memoized.utility?(first) } }.to raise_error(Encoding::CompatibilityError)
      expect(first).to have_received(:unicode_normalize).once
    end
  end

  describe 'page language' do
    let(:scoped) { ->(lang) { described_class.new(vocabulary: Html2rss::Vocabulary[lang]) } }

    it 'reads an ambiguous term only in its own language or all', :aggregate_failures do
      text = 'Dela Cruz wins election'

      expect(scoped.call(:en).utility?(text)).to be(false)
      expect(scoped.call(:sv).utility?(text)).to be(true)
      expect(scoped.call(nil).utility?(text)).to be(true)
      expect(described_class.new.utility?(text)).to be(true)
    end

    it 'reads an unambiguous term in every language', :aggregate_failures do
      %i[en de sv ja].each do |lang|
        expect(scoped.call(lang).utility?('Newsletter')).to be(true), lang.to_s
        expect(scoped.call(lang).utility_prefix?('Subscribe now')).to be(true), lang.to_s
      end
    end

    it 'scopes the prefix and the recommendation readings alike', :aggregate_failures do
      expect(scoped.call(:fr).utility_prefix?('Plus de 100 morts')).to be(false)
      expect(scoped.call(:en).utility_prefix?('Plus membership')).to be(true)
      expect(scoped.call(:ja).recommended?('Recommended for you')).to be(true)
      expect(scoped.call(:fr).recommended?('Recommended for you')).to be(true)
    end

    it 'leaves read-more labels in every language', :aggregate_failures do
      %i[en de sv].each { |lang| expect(scoped.call(lang).read_more?('Lire la suite')).to be(true), lang.to_s }
    end
  end
end
