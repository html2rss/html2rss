# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Class and id tokens that mark an element as content or as junk, read by
    # {Scoring::LinkResolver::CONTENT_TOKEN_REGEXP} and {Scoring::LinkResolver::JUNK_TOKEN_REGEXP}. A list of its
    # own, apart from the path words: a CSS token is matched as a whole space, hyphen or underscore delimited
    # word, a path segment as a folded URL segment. Both lists are frozen sets of lowercase words.
    module CssTokens
      # Tokens that mark an article, post or card.
      CONTENT = Set.new(
        %w[
          actualite actualites aggiornamenti aktualnosci aktualności aktuelles
          article articles articoli articolo articulo articulos
          artikel artikelen artiklar artykul artykuly artykuł
          artykuły beitraege beitrag bericht berichten blog
          blogs card cards changelog changelogs entrada
          entradas inlagg inlägg insight insights launch
          launches nachrichten neuigkeiten news nieuws nieuwsberichten
          noticia noticias notizia notizie nouvelle nouvelles
          novita novità nyhet nyheter post posts
          publicacion publicaciones release releases stories story
          teaser teasers update updates wiadomosci wiadomości
          wpis wpisy お知らせ ニュース ブログ 記事
        ]
      ).freeze
      # Tokens that mark navigation, account, commerce and other page chrome.
      JUNK = Set.new(
        %w[
          a-propos abo abonnieren about account ad
          ads agb aide anmelden anmeldung apropos
          archiv archive archives archivos auteur auteurs
          author authors autor autoren autores ayuda
          banner boletin broker buscar busqueda career
          careers casino casinos categoria categorias categorie
          categories category cgu comment comment-feed comments
          comments-feed comparison compte condiciones confidentialite connexion
          contact cookie cookies crypto cuenta datenschutz
          dating deal deals echtgeld entrar etiqueta
          etiquetas etiquette etiquettes feed feedback feeds
          for-you help hilfe impressum ingresar inscription
          insurance job jobs join kategorie kategorien
          kaufberater kontakt konto kredit kreditkarte kreditkarten
          krypto leasing lettre-information login logout member
          members membership mentions-legales menu modal newsletter
          newsletters notification notifications nutzungsbedingungen pager pagination
          partnerboerse plans plus popup preference preferences
          premium pricing privacidad privacy profil profile
          promo quienes-somos recherche rechercher recommendation recommendations
          recommended register registrarse registrieren registrierung registro
          related s-abonner s-inscrire saboner schlagwort schlagworte
          search settings share shop shopping sidebar
          signup singleboerse sinscrire sobre sobre-nosotros social
          subscribe suche sujet sujets suscribirse tag
          tags tema temas terms thema theme
          themen themes tierversicherung topic topics trading
          ueber ueber-uns ueberuns user users vergleich
          versicherung vpn widget
        ]
      ).freeze
    end
  end
end
