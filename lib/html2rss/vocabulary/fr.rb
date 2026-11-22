# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # French.
    Fr = Language.new(
      code: :fr,
      terms: {
        path_section: %w[actualites nouvelles],
        path_article: %w[actualite nouvelle],
        path_profile: %w[auteur auteurs journaliste journalistes],
        path_office: %w[redaction rédaction],
        path_non_article: %w[jeux necrologie nécrologie endirect],
        path_taxonomy: %w[categorie etiquette etiquettes sujet sujets theme themes],
        path_vanity: %w[s-abonner saboner],
        path_soft_utility: NONE,
        path_chrome: %w[
          auteur auteurs a-propos apropos recherche rechercher aide connexion s-inscrire sinscrire inscription
          compte s-abonner saboner lettre-information confidentialite mentions-legales cgu
        ],
        path_media: %w[vidéo vidéos],
        path_deep_post_context: NONE,
        type_marker: ['vidéo', 'diaporama', 'en direct', 'communiqué de presse', 'épisode complet'],
        utility_prefix: [
          'voir tout', 'voir tous', 'toutes les nouvelles', /s['’]abonner/, 'flux de commentaires', 'rejoindre'
        ],
        utility: [
          'a propos', 'à propos', 'apropos', 'àpropos', 'contact', 'commentaire', 'commentaires', 'rejoindre',
          'se connecter', 'login', 'membre', 'abonnement', 'voir tout', 'partager', /s['’]inscrire/,
          /s['’]abonner/, 'newsletter'
        ],
        recommended: ['recommande', 'recommandé', 'recommande pour vous', 'recommandé pour vous'],
        read_more: [
          'lire la suite', 'lire plus', /lire\s+l['’]article(?:\s+complet)?/, 'en savoir plus',
          'pour en savoir plus', /plus\s+d['’]infos?/, /plus\s+d['’]informations?/
        ],
        topic_lead: [/plus\s+d['’]infos?/],
        topic_preposition: ['sur', /(?:à|a)\s+propos\s+de/, 'de'],
        read_more_suffix: NONE,
        new_window_notice: [/ouvre\s+dans\s+(?:une\s+)?nouvel(?:le)?\s+(?:fen(?:ê|e)tre|onglet)/],
        paid_label: [
          /(?:contenu\s+)?sponsoris(?:e|é)(?:\s+par(?:\s+\S+){0,5})?/, 'publireportage', /contenus?\s+partenaires?/
        ],
        ad_word: [/publicit(?:e|é)/],
        field_label: ['rubrique', /cat(?:é|e)gorie/, /th(?:è|e)me/],
        type_label: [/type\s+d['’]article/, 'type de contenu'],
        pager_label: NONE,
        page_link: NONE,
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE
      }.freeze,
      ambiguous: {
        path_taxonomy: %w[theme themes]
      }.freeze
    )
  end
end
