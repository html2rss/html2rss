# frozen_string_literal: true

module Html2rss
  module LinkDestination
    # Classifies visible anchor text for utility, recommendation and read-more chrome in en, de, fr, es, it,
    # nl, pl, sv and ja. Letters with an accented variant are alternations, not classes: with +/i+, Ruby on
    # Linux does not fold an uppercase accented letter against a class that also holds its ASCII base.
    class TextClassifier # rubocop:disable Metrics/ClassLength -- nine-language vocabulary tables
      # Prefix labels that usually identify navigation or subscription links.
      UTILITY_PREFIX_PATTERN = /
        \A\s*(
          # English
          view\s+all|see\s+all|all\s+news|subscribe|newsletter|comment\s+feed|comments\s+feed|join|premium|plus|
          # German
          alle\s+anzeigen|alle\s+news|abonnieren|newsletter|kommentar\s+feed|mitmachen|
          # Spanish
          ver\s+todos|ver\s+todo|todas\s+las\s+noticias|suscribirse|bolet(i|í)n|comentarios\s+feed|unirse|
          # French
          voir\s+tout|voir\s+tous|toutes\s+les\s+nouvelles|s['’]abonner|flux\s+de\s+commentaires|rejoindre|
          # Italian
          vedi\s+tutto|vedi\s+tutti|tutte\s+le\s+notizie|abbonati|newsletter|iscriviti|
          # Dutch
          bekijk\s+alles|alles\s+bekijken|al\s+het\s+nieuws|abonneren|nieuwsbrief|lid\s+worden|
          # Polish
          zobacz\s+wszystko|wszystkie\s+wiadomo(ś|s)ci|subskrybuj|newsletter|do(łą|la)cz|
          # Swedish
          visa\s+alla|se\s+alla|alla\s+nyheter|prenumerera|nyhetsbrev|bli\s+medlem|
          # Japanese
          すべて見る|全て見る|ニュースレター|メルマガ|会員登録|購読
        )\b
      /ix
      # Short labels that usually identify non-article navigation links.
      UTILITY_PATTERN = /
        \A\s*(
          # English
          about|contact|comments?|join|log\s+in|login|member(ship)?|
          plus|premium|pricing|recommended(\s+for\s+you)?|
          see\s+all|share|sign\s+up|signup|subscribe|view\s+all|
          # German
          (ue|ü)ber(\s+uns)?|kontakt|kommentare?|mitmachen|anmelden|login|
          mitglied(schaft)?|empfohlen(\s+f(ue|ü)r\s+dich)?|alle\s+anzeigen|
          teilen|registrieren|abonnieren|newsletter|
          # Spanish
          sobre(\s+nosotros)?|contacto|comentarios?|unirse|iniciar\s+sesion|
          login|miembro|membres(i|í)a|recomendado(\s+para\s+ti)?|ver\s+todo|
          compartir|registrarse|suscribirse|bolet(i|í)n|
          # French
          (a|à)\s+propos|(a|à)propos|contact|commentaires?|rejoindre|
          se\s+connecter|login|membre|abonnement|recommand(e|é)(\s+pour\s+vous)?|
          voir\s+tout|partager|s['’]inscrire|s['’]abonner|newsletter|
          # Italian
          chi\s+siamo|contatti|commenti|accedi|iscriviti|condividi|abbonati|registrati|vedi\s+tutto|
          consigliato(\s+per\s+te)?|abbonamento|
          # Dutch
          over\s+ons|contact|reacties|inloggen|aanmelden|delen|abonneren|registreren|bekijk\s+alles|
          aanbevolen(\s+voor\s+jou)?|nieuwsbrief|lid\s+worden|lidmaatschap|
          # Polish
          o\s+nas|kontakt|komentarze|zaloguj\s+si(ę|e)|zarejestruj\s+si(ę|e)|udost(ę|e)pnij|subskrybuj|
          zobacz\s+wszystko|polecane(\s+dla\s+ciebie)?|do(łą|la)cz|
          # Swedish
          om\s+oss|kontakt|kommentarer|logga\s+in|bli\s+medlem|dela|prenumerera|registrera\s+dig|visa\s+alla|
          se\s+alla|rekommenderat(\s+f(ö|o)r\s+dig)?|nyhetsbrev|medlemskap|
          # Japanese
          会社概要|お問い合わせ|コメント|ログイン|会員登録|新規登録|シェア|共有|購読|すべて見る|全て見る|
          もっと見る|おすすめ|ニュースレター|メルマガ
        )\b
      /ix
      # Labels for recommendation chrome rather than source articles.
      RECOMMENDED_PATTERN = /
        \A\s*(
          recommended(\s+for\s+you)?|
          empfohlen(\s+f(ue|ü)r\s+dich)?|
          recomendado(\s+para\s+ti)?|
          recommand(e|é)(\s+pour\s+vous)?|
          consigliato(\s+per\s+te)?|
          aanbevolen(\s+voor\s+jou)?|
          polecane(\s+dla\s+ciebie)?|
          rekommenderat(\s+f(ö|o)r\s+dig)?|
          おすすめ
        )\b
      /ix

      # Whole read-more labels that stand alone ("Continue reading", "Lire la suite", "続きを読む").
      READ_MORE_PHRASE = /
        read\s+more|read\s+on|continue\s+reading|keep\s+reading|learn\s+more|find\s+out\s+more|
        read\s+(?:the\s+)?(?:full\s+|whole\s+)?(?:story|article)|read\s+the\s+rest|
        weiterlesen|weiter\s+lesen|mehr\s+lesen|mehr\s+erfahren|mehr\s+dazu|mehr\s+zum\s+thema|
        lesen\s+sie\s+(?:mehr|weiter)|(?:den\s+)?(?:ganzen|gesamten|vollst(?:ä|a)ndigen)\s+artikel\s+lesen|
        lire\s+la\s+suite|lire\s+plus|lire\s+l['’]article(?:\s+complet)?|en\s+savoir\s+plus|
        pour\s+en\s+savoir\s+plus|plus\s+d['’]infos?|plus\s+d['’]informations?|
        leer\s+m(?:á|a)s|seguir\s+leyendo|continuar\s+leyendo|saber\s+m(?:á|a)s|
        m(?:á|a)s\s+informaci(?:ó|o)n|leer\s+(?:todo|el\s+art(?:í|i)culo\s+completo)|
        leggi\s+tutto|leggi\s+di\s+pi(?:ù|u)|leggi\s+l['’]articolo|continua\s+a\s+leggere|scopri\s+di\s+pi(?:ù|u)|
        maggiori\s+informazioni|ulteriori\s+informazioni|per\s+saperne\s+di\s+pi(?:ù|u)|approfondisci|
        lees\s+meer|lees\s+verder|verder\s+lezen|meer\s+lezen|meer\s+informatie|meer\s+weten|
        lees\s+(?:het\s+)?(?:hele|volledige)\s+artikel|
        czytaj\s+wi(?:ę|e)cej|czytaj\s+dalej|dowiedz\s+si(?:ę|e)\s+wi(?:ę|e)cej|wi(?:ę|e)cej\s+informacji|
        czytaj\s+ca(?:ł|l)o(?:ś|s)(?:ć|c)|zobacz\s+wi(?:ę|e)cej|
        l(?:ä|a)s\s+mer|l(?:ä|a)s\s+vidare|forts(?:ä|a)tt\s+l(?:ä|a)sa|mer\s+information|
        l(?:ä|a)s\s+hela\s+artikeln|
        続きを読む|もっと読む|続きはこちら|詳しくはこちら|詳細を見る|詳細はこちら|全文を読む|続きを見る
      /ix
      # "More about X" lead-ins: a read-more phrase or a bare "more", then a topic preposition.
      READ_MORE_TOPIC_LEAD = /
        (?:#{READ_MORE_PHRASE.source}|more|mehr|plus\s+d['’]infos?|m(?:á|a)s|altro|di\s+pi(?:ù|u)|meer|wi(?:ę|e)cej|mer)
        \s+(?:about|on|from|zu|zum\s+thema|zum|zur|(?:ü|ue)ber|von|sur|
        (?:à|a)\s+propos\s+de|de|sobre|su|riguardo|over|van|
        o|na\s+temat|om|av)
      /ix
      # A read-more label as a whole text, optionally wrapped in punctuation or arrows. The topic after a
      # lead-in counts only when quoted ("More about «X»", „X“, "X", 'X', 「X」), so a headline that merely
      # opens with one ("Mehr über die Zukunft der Rente") stays a headline; Japanese topic forms put the
      # topic first.
      READ_MORE_PATTERN = /
        \A[\s\p{P}\p{S}]*(?:
          (?:#{READ_MORE_PHRASE.source})|
          (?:#{READ_MORE_TOPIC_LEAD.source})\s*[«„"“”'‘’‹「].+[»"“”'’›」]|
          \S{1,40}(?:の続きを読む|をもっと読む|について詳しく(?:はこちら)?|の詳細(?:を見る|はこちら))
        )[\s\p{P}\p{S}]*\z
      /ix

      # Visible new-window notice that trails a link label, in parentheses or brackets.
      NEW_WINDOW_NOTICE = /
        \s*[(\[（【]\s*(?:
          opens\s+in\s+(?:a\s+)?new\s+(?:window|tab)|
          (?:ö|oe)ffnet\s+(?:sich\s+)?in\s+(?:einem\s+neuen|neuem)\s+(?:fenster|tab)|
          ouvre\s+dans\s+(?:une\s+)?nouvel(?:le)?\s+(?:fen(?:ê|e)tre|onglet)|
          se\s+abre\s+en\s+(?:una\s+)?nueva\s+(?:ventana|pesta(?:ñ|n)a)|
          si\s+apre\s+in\s+(?:una\s+)?nuova\s+(?:finestra|scheda)|
          opent\s+in\s+(?:een\s+)?nieuw(?:e)?\s+(?:venster|tabblad)|
          otwiera\s+si(?:ę|e)\s+w\s+nowym\s+(?:oknie|karcie)|
          (?:ö|o)ppnas\s+i\s+(?:ett\s+)?nytt\s+(?:f(?:ö|o)nster|flik)|
          新しい(?:ウィンドウ|ウインドウ|タブ)で開く
        )\s*[)\]）】]\s*\z
      /ix

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text matches a utility label
      def utility?(text) = normalize(text).match?(UTILITY_PATTERN)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text begins with a utility label
      def utility_prefix?(text) = normalize(text).match?(UTILITY_PREFIX_PATTERN)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text identifies recommendation chrome
      def recommended?(text) = normalize(text).match?(RECOMMENDED_PATTERN)

      # @param text [String, #to_s] visible anchor text or extracted title
      # @return [Boolean] true when the whole text is a read-more label, bare or with its topic
      def read_more?(text) = normalize(text).match?(READ_MORE_PATTERN)

      private

      # Every label is read in NFC, so a decomposed accent matches the precomposed vocabulary, and without
      # its trailing new-window notice ("(opens in new tab)").
      def normalize(text) = text.to_s.unicode_normalize(:nfc).sub(NEW_WINDOW_NOTICE, '')
    end
  end
end
