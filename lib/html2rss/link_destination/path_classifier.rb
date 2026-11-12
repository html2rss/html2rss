# frozen_string_literal: true

module Html2rss
  module LinkDestination
    # Classifies normalized destination path segments for scoring.
    class PathClassifier # rubocop:disable Metrics/ClassLength
      attr_reader :segments

      # Soft utility segments excluded from high-confidence junk (still utility_path).
      SOFT_UTILITY = Set[
        'for-you', 'join', 'member', 'members', 'membership', 'newsletter', 'newsletters',
        'plans', 'plus', 'premium', 'pricing', 'recommended'
      ].freeze

      # Segment groups used to classify article, taxonomy, utility, and vanity routes.
      # Utility = taxonomy ∪ chrome ∪ soft utility (do not re-list taxonomy tokens).
      SEGMENT_SETS = begin
        # Listing words: a path ending in one is a section index, not an article.
        section = Set[
          'articles', 'blog', 'blogs', 'changelogs', 'insights', 'launches', 'news', 'posts', 'releases',
          'stories', 'updates', 'nachrichten', 'neuigkeiten', 'aktuelles', 'beitraege', 'articulos', 'noticias',
          'entradas', 'publicaciones', 'actualites', 'nouvelles', 'teasers', 'cards',
          'aktualnosci', 'aktualności', 'wiadomosci', 'wiadomości', 'artykuly', 'artykuły', 'wpisy', 'notizie',
          'articoli', 'novita', 'novità', 'aggiornamenti', 'nieuws', 'nieuwsberichten', 'artikelen', 'berichten',
          'nyheter', 'artiklar', 'ニュース', '記事', 'お知らせ', 'ブログ'
        ].freeze
        content = (section | Set[
          'article', 'changelog', 'insight', 'launch', 'post', 'release', 'story', 'update', 'artikel', 'beitrag',
          'articulo', 'noticia', 'entrada', 'publicacion', 'actualite', 'nouvelle', 'teaser', 'card',
          'artykul', 'artykuł', 'wpis', 'notizia', 'articolo', 'bericht', 'nyhet', 'inlagg', 'inlägg'
        ]).freeze
        # People pages. `team` and `people` are left out on purpose: they name sports teams and
        # newsmakers in article paths. The words below are unambiguous byline/staff words.
        profile = Set[
          'author', 'authors', 'staff', 'journalist', 'journalists', 'players',
          'autor', 'autoren', 'redakteure', 'autores', 'periodista',
          'periodistas', 'auteur', 'auteurs', 'journaliste', 'journalistes',
          'autore', 'autori', 'giornalista', 'giornalisti', 'journalisten',
          'autorzy', 'dziennikarz', 'dziennikarze', 'skribent', 'skribenter', 'forfattare',
          'författare', '著者', '執筆者', '記者', 'ライター'
        ].freeze
        # Editorial-office and contributor words: their child pages are often editorial notes with a
        # three-word slug, so only a one- or two-word name slug marks a profile.
        office = Set[
          'contributor', 'contributors', 'redaktion', 'redaccion', 'redacción', 'redaction', 'rédaction',
          'redazione', 'redactie', 'redakcja', '編集部'
        ].freeze
        # Destinations that are never articles: games, horoscopes, quizzes, obituaries, livestreams, players.
        non_article = Set[
          'games', 'spiele', 'juegos', 'jeux', 'giochi', 'spellen', 'spel', 'gry', 'ゲーム',
          'sudoku', 'crossword', 'crosswords', 'kreuzwortraetsel', 'kreuzworträtsel', 'crucigrama', 'crucigramas',
          'quiz', 'quizzes', 'quizze', 'quizzen', 'kviz', 'クイズ',
          'horoscope', 'horoscopes', 'horoskop', 'horoskope', 'horoscopo', 'horoscopos', 'oroscopo', 'oroscopi',
          'horoscoop', 'horoskopy', '星座占い', '占い',
          'obituary', 'obituaries', 'nachruf', 'nachrufe', 'traueranzeigen', 'todesanzeigen', 'necrologie',
          'nécrologie', 'necrologio', 'necrologi', 'esquelas', 'obituarios', 'overlijdensberichten', 'nekrolog',
          'nekrologi', 'dodsannonser', 'dödsannonser', '訃報', 'おくやみ',
          'livestream', 'livestreams', 'endirect', 'envivo', 'indiretta', 'nazywo', 'ライブ配信',
          'player'
        ].freeze
        taxonomy = Set[
          'category', 'categories', 'tag', 'tags', 'topic', 'topics',
          'kategorie', 'kategorien', 'schlagwort', 'schlagworte', 'thema', 'themen',
          'categoria', 'categorias', 'etiqueta', 'etiquetas', 'tema', 'temas',
          'categorie', 'etiquette', 'etiquettes', 'sujet', 'sujets', 'theme', 'themes'
        ].freeze
        vanity = Set[
          'join', 'membership', 'plus', 'premium', 'pricing', 'plans', 'subscribe', 'signup',
          'abonnieren', 'abo', 'suscribirse', 'boletin', 's-abonner', 'saboner'
        ].freeze
        chrome = Set[
          'about', 'account', 'archive', 'archives', 'author', 'authors', 'comment', 'comments',
          'contact', 'feedback', 'help', 'login', 'logout', 'notification', 'notifications',
          'preference', 'preferences', 'profile', 'register', 'search', 'settings', 'share',
          'signup', 'subscribe', 'feed', 'feeds', 'comment-feed', 'comments-feed', 'privacy',
          'terms', 'cookie', 'cookies', 'user', 'users', 'autor', 'autoren', 'archiv', 'ueber-uns',
          'ueber', 'ueberuns', 'profil', 'kontakt', 'impressum', 'suche', 'hilfe', 'anmelden',
          'registrieren', 'konto', 'registrierung', 'anmeldung', 'abonnieren', 'abo', 'datenschutz',
          'nutzungsbedingungen', 'agb', 'autores', 'archivos', 'sobre-nosotros', 'sobre',
          'quienes-somos', 'buscar', 'busqueda', 'ayuda', 'entrar', 'ingresar', 'registrarse',
          'registro', 'cuenta', 'suscribirse', 'boletin', 'privacidad', 'condiciones', 'auteur',
          'auteurs', 'a-propos', 'apropos', 'recherche', 'rechercher', 'aide', 'connexion',
          's-inscrire', 'sinscrire', 'inscription', 'compte', 's-abonner', 'saboner',
          'lettre-information', 'confidentialite', 'mentions-legales', 'cgu', 'menu', 'sidebar',
          'widget', 'social', 'modal', 'popup', 'banner', 'promo', 'ad', 'ads', 'related',
          'recommendation', 'recommendations', 'pagination', 'pager', 'dating', 'jobs', 'job',
          'career', 'careers', 'deals', 'deal', 'shopping', 'shop', 'trading', 'broker',
          'versicherung', 'tierversicherung', 'insurance', 'vergleich', 'comparison',
          'partnerboerse', 'singleboerse', 'krypto', 'crypto', 'casinos', 'casino',
          'kreditkarten', 'kreditkarte', 'kredit', 'echtgeld', 'vpn', 'kaufberater',
          'leasing'
        ].freeze
        utility = (taxonomy | chrome | SOFT_UTILITY).freeze
        {
          content:,
          section:,
          utility:,
          high_confidence_junk: (utility - SOFT_UTILITY).freeze,
          taxonomy:,
          non_article:,
          profile:,
          office:,
          people_index: (profile | office).freeze,
          vanity:,
          deep_post_context: Set['press', 'newsroom', 'presse', 'pressemitteilungen', 'prensa'].freeze
        }.freeze
      end
      # Path segment that begins with a year-like publishing marker.
      YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
      # Hyphenated slug shape common to article permalinks.
      POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i
      # Multi-label host mistaken for a path segment (affiliate/outlink chrome).
      # Final label must be alphabetic (TLD-like); exclude common file extensions.
      HOST_SHAPED_SEGMENT = /\A(?:www\.)?(?:[\w-]+\.)+[a-z]{2,24}\z/i
      # Common file-extension suffixes excluded from host-shaped junk matching.
      FILE_EXTENSION_SEGMENT = /\.(?:pdf|jpe?g|png|gif|svg|webp|css|js|mjs|html?|xml|json|mp4|webm|zip|gz)\z/i

      # A single person-name slug: letters only (dated and id slugs carry digits), up to three words.
      NAME_SLUG = /\A\p{L}+(?:-\p{L}+){0,2}\z/
      # Name slug of at most two words, for office/contributor sections whose notes carry longer slugs.
      SHORT_NAME_SLUG = /\A\p{L}+(?:-\p{L}+)?\z/
      # Name-slug shape that marks a profile page, by the word set of its parent segment.
      NAME_SLUG_BY_OWNER = { profile: NAME_SLUG, office: SHORT_NAME_SLUG }.freeze

      # Pop-up / embedded player segments such as `popup-audio-player` (hyphens removed before matching).
      PLAYER_SEGMENT = /\A(?:(?:pop(?:up|out)|embed|audio|video|media)\w*)?player\z/

      # @param segments [Array<String>] normalized URL path segments
      # @param host_label [String, nil] first host label (e.g. an obituary subdomain)
      # @param query [Boolean] whether the URL carries a query string (`/blog?p=12` selects one post)
      def initialize(segments, host_label: nil, query: false)
        @segments = segments
        @query = query
        @host_label = host_label.to_s.downcase
        @lexicon = segments.map { ::Html2rss::Html::Probe.fold(_1) }.freeze
      end

      # @return [Boolean] true when the route has article-like path evidence
      def content_path?
        @content_path ||= !leading_high_confidence_junk? &&
                          (SEGMENT_SETS[:content].intersect?(@lexicon) || yearish_content_context?)
      end

      # @return [Boolean] true when the route includes utility/navigation evidence
      def utility_path?
        @utility_path ||= SEGMENT_SETS[:utility].intersect?(@lexicon)
      end

      # @return [Boolean] true when the route points at conversion or account chrome
      def vanity_path?
        @vanity_path ||= SEGMENT_SETS[:vanity].intersect?(@lexicon)
      end

      # @return [Boolean] true when the route points at taxonomy/listing chrome
      def taxonomy_path?
        @taxonomy_path ||= SEGMENT_SETS[:taxonomy].intersect?(@lexicon)
      end

      # @return [Boolean] true when the route is too shallow to strongly indicate an article
      def shallow?
        segment_count = segments.size

        segment_count <= 1 || (segment_count == 2 && high_confidence_junk_at?(1))
      end

      # @return [Boolean] true when the final path segment looks like a post slug
      def strong_post_suffix?
        @strong_post_suffix ||= segments.any? &&
                                slug_last_segment? &&
                                trusted_post_context?(segments.size - 1)
      end

      # @return [Boolean] true when every path segment is utility chrome
      def utility_only_route?
        (0...segments.size).all? { |i| high_confidence_junk_at?(i) }
      end

      # @return [Boolean] true when the route is shallow and names a soft vanity segment
      def shallow_vanity_route?
        shallow? && @lexicon.any? { |folded| SEGMENT_SETS.fetch(:vanity).include?(folded) }
      end

      # @return [Boolean] true when the leading segments are all utility chrome
      def deep_utility_context_route?
        all_junk?(segments.size - 1)
      end

      # @return [Boolean] true when the host or a path segment names a game, horoscope, quiz,
      #   obituary, livestream or player destination, or the path is a bare section index
      def non_article_path?
        return @non_article_path if defined?(@non_article_path)

        @non_article_path = section_index? || profile_route? || (!strong_post_suffix? && non_article_word_present?)
      end

      # @return [Boolean] true when the route is shallow and contains high-confidence noise
      def junk_path?
        return true if non_article_path?
        return false if excluded_content_route?

        any_high_confidence_junk_segment? || shallow_vanity_route?
      end

      # @return [Boolean] true when the route points at conversion or account chrome
      def utility_destination?
        return true if non_article_path?
        return false if excluded_content_route?

        vanity_path? || utility_route?
      end

      private

      def non_article_word_present?
        ([@host_label] + @lexicon).any? { non_article_word?(_1) }
      end

      def non_article_word?(word)
        joined = word.delete('-_')
        SEGMENT_SETS[:non_article].include?(joined) || joined.match?(PLAYER_SEGMENT)
      end

      # A people word that ends the path (an index) or is followed by one name slug (a profile page).
      def profile_route?
        return false if segments.empty?

        SEGMENT_SETS[:people_index].include?(@lexicon.last) || profile_page?
      end

      def profile_page?
        return false if segments.size < 2

        NAME_SLUG_BY_OWNER.any? { |set, slug| SEGMENT_SETS[set].include?(@lexicon[-2]) && segments.last.match?(slug) }
      end

      # A path ending in a section word (no slug) lists articles instead of being one.
      def section_index?
        !@query && segments.any? && SEGMENT_SETS[:section].include?(@lexicon.last)
      end

      def leading_high_confidence_junk?
        segments.any? && high_confidence_junk_at?(0)
      end

      def any_high_confidence_junk_segment?
        (0...segments.size).any? { |i| high_confidence_junk_at?(i) }
      end

      def yearish_content_context?
        segments.any? { |segment| segment.match?(YEARISH_SEGMENT) } && trusted_post_context?(segments.size - 1)
      end

      def excluded_content_route?
        segments.empty? || content_path? || strong_post_suffix?
      end

      def utility_route?
        taxonomy_path? ||
          utility_only_route? ||
          deep_utility_context_route? ||
          shallow_utility_route?
      end

      def shallow_utility_route?
        shallow? && utility_path?
      end

      def all_junk?(limit)
        return false if limit <= 0

        (0...limit).all? { |i| high_confidence_junk_at?(i) }
      end

      def high_confidence_junk_at?(index)
        SEGMENT_SETS.fetch(:high_confidence_junk).include?(@lexicon[index]) ||
          host_shaped_segment?(segments[index])
      end

      def host_shaped_segment?(segment)
        segment.match?(HOST_SHAPED_SEGMENT) && !segment.match?(FILE_EXTENSION_SEGMENT)
      end

      def trusted_post_context?(limit)
        return false if leading_high_confidence_junk?

        content = SEGMENT_SETS.fetch(:content)
        context = SEGMENT_SETS.fetch(:deep_post_context)
        segments.zip(@lexicon).first(limit.clamp(0..)).any? do |segment, folded|
          content.include?(folded) || segment.match?(YEARISH_SEGMENT) || context.include?(folded)
        end
      end

      def slug_last_segment?
        last = segments.last
        last.match?(YEARISH_SEGMENT) || last.match?(POST_SLUG_SEGMENT)
      end
    end
  end
end
