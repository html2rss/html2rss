# frozen_string_literal: true

module Html2rss
  module Scoring
    # Classifies visible anchor text for utility and recommendation chrome.
    class TextClassifier
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
          voir\s+tout|voir\s+tous|toutes\s+les\s+nouvelles|s['’]abonner|flux\s+de\s+commentaires|rejoindre
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
          voir\s+tout|partager|s['’]inscrire|s['’]abonner|newsletter
        )\b
      /ix
      # Labels for recommendation chrome rather than source articles.
      RECOMMENDED_PATTERN = /
        \A\s*(
          recommended(\s+for\s+you)?|
          empfohlen(\s+f(ue|ü)r\s+dich)?|
          recomendado(\s+para\s+ti)?|
          recommand(e|é)(\s+pour\s+vous)?
        )\b
      /ix

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text matches a utility label
      def utility?(text) = text.to_s.match?(UTILITY_PATTERN)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text begins with a utility label
      def utility_prefix?(text) = text.to_s.match?(UTILITY_PREFIX_PATTERN)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text identifies recommendation chrome
      def recommended?(text) = text.to_s.match?(RECOMMENDED_PATTERN)
    end
  end
end
