# frozen_string_literal: true

module Html2rss
  module LinkDestination
    # Classifies normalized destination path segments for scoring.
    class PathClassifier # rubocop:disable Metrics/ClassLength
      attr_reader :segments

      # Soft utility segments excluded from high-confidence junk (still utility_path).
      SOFT_UTILITY = %w[
        for-you join member members membership newsletter newsletters
        plans plus premium pricing recommended
      ].to_set.freeze

      # Segment groups used to classify article, taxonomy, utility, and vanity routes.
      SEGMENT_SETS = begin
        content = %w[
          article articles blog blogs changelog changelogs insight insights
          launch launches news post posts release releases story stories update updates
          artikel beitrag beitraege nachrichten neuigkeiten aktuelles
          articulo articulos noticia noticias entrada entradas publicacion publicaciones
          actualite actualites nouvelle nouvelles teaser teasers card cards
        ].to_set.freeze
        taxonomy = %w[
          category categories tag tags topic topics
          kategorie kategorien schlagwort schlagworte thema themen
          categoria categorias etiqueta etiquetas tema temas
          categorie etiquette etiquettes sujet sujets theme themes
        ].to_set.freeze
        vanity = %w[
          join membership plus premium pricing plans subscribe signup
          abonnieren abo suscribirse boletin s-abonner saboner
        ].to_set.freeze
        utility = (
          taxonomy.to_a + %w[
            about account archive archives author authors comment comments
            contact feedback help login logout notification notifications
            preference preferences profile register search settings share signup subscribe
            feed feeds comment-feed comments-feed privacy terms cookie cookies user users
            kategorie kategorien schlagwort schlagworte thema themen autor autoren archiv
            ueber-uns ueber ueberuns profil kontakt impressum suche hilfe anmelden registrieren
            konto registrierung anmeldung abonnieren abo datenschutz nutzungsbedingungen agb
            categoria categorias etiqueta etiquetas tema temas autores archivos
            sobre-nosotros sobre quienes-somos buscar busqueda ayuda entrar ingresar
            registrarse registro cuenta suscribirse boletin privacidad condiciones
            categorie etiquette etiquettes sujet sujets theme themes auteur auteurs
            a-propos apropos recherche rechercher aide connexion s-inscrire
            sinscrire inscription compte s-abonner saboner lettre-information confidentialite
            mentions-legales cgu menu sidebar widget social modal popup banner promo ad ads
            related recommendation recommendations pagination pager
            dating jobs job career careers deals deal shopping shop trading broker
            versicherung tierversicherung insurance vergleich comparison
            partnerboerse singleboerse krypto crypto
            casinos casino kreditkarten kreditkarte echtgeld
          ] + SOFT_UTILITY.to_a
        ).to_set.freeze
        {
          content:,
          utility:,
          high_confidence_junk: (utility - SOFT_UTILITY).freeze,
          taxonomy:,
          vanity:,
          deep_post_context: %w[press newsroom presse pressemitteilungen prensa].to_set.freeze
        }.freeze
      end
      # Path segment that begins with a year-like publishing marker.
      YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
      # Hyphenated slug shape common to article permalinks.
      POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i
      # Multi-label host mistaken for a path segment (affiliate/outlink chrome).
      # Final label must be alphabetic (TLD-like); exclude common file extensions.
      HOST_SHAPED_SEGMENT = /\A(?:www\.)?(?:[\w-]+\.)+[a-z]{2,24}\z/i
      FILE_EXTENSION_SEGMENT = /\.(?:pdf|jpe?g|png|gif|svg|webp|css|js|mjs|html?|xml|json|mp4|webm|zip|gz)\z/i

      # @param segments [Array<String>] normalized URL path segments
      def initialize(segments)
        @segments = segments
      end

      # @return [Boolean] true when the route has article-like path evidence
      def content_path?
        @content_path ||= SEGMENT_SETS[:content].intersect?(segments) ||
                          yearish_content_context?
      end

      # @return [Boolean] true when the route includes utility/navigation evidence
      def utility_path?
        @utility_path ||= SEGMENT_SETS[:utility].intersect?(segments)
      end

      # @return [Boolean] true when the route points at conversion or account chrome
      def vanity_path?
        @vanity_path ||= SEGMENT_SETS[:vanity].intersect?(segments)
      end

      # @return [Boolean] true when the route points at taxonomy/listing chrome
      def taxonomy_path?
        @taxonomy_path ||= SEGMENT_SETS[:taxonomy].intersect?(segments)
      end

      # @return [Boolean] true when the route is too shallow to strongly indicate an article
      def shallow?
        segment_count = segments.size

        segment_count <= 1 || (segment_count == 2 && high_confidence_junk_segment?(segments.last))
      end

      # @return [Boolean] true when the final path segment looks like a post slug
      def strong_post_suffix?
        @strong_post_suffix ||= segments.any? &&
                                included_last_segment? &&
                                trusted_post_context?(segments.size - 1)
      end

      # @return [Boolean] true when every path segment is utility chrome
      def utility_only_route?
        segments.all? { |segment| high_confidence_junk_segment?(segment) }
      end

      # @return [Boolean] true when the route is shallow and contains high-confidence noise
      def shallow_high_confidence_route?
        vanity_segments = SEGMENT_SETS.fetch(:vanity)

        shallow? && segments.any? do |segment|
          high_confidence_junk_segment?(segment) || vanity_segments.include?(segment)
        end
      end

      # @return [Boolean] true when the leading segments are all utility chrome
      def deep_utility_context_route?
        all_junk?(segments.size - 1)
      end

      # @return [Boolean] true when the route is shallow and contains high-confidence noise
      def junk_path?
        return false if excluded_content_route?

        taxonomy_path? ||
          utility_only_route? ||
          deep_utility_context_route? ||
          shallow_high_confidence_route?
      end

      # @return [Boolean] true when the route points at conversion or account chrome
      def utility_destination?
        return false if excluded_content_route?

        vanity_path? || utility_route?
      end

      private

      def yearish_content_context?
        segments.any? { |segment| segment.match?(YEARISH_SEGMENT) } &&
          (strong_post_suffix? || trusted_post_context?(segments.size - 1))
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

        (0...limit).all? { |i| high_confidence_junk_segment?(segments[i]) }
      end

      def high_confidence_junk_segment?(segment)
        SEGMENT_SETS.fetch(:high_confidence_junk).include?(segment) || host_shaped_segment?(segment)
      end

      def host_shaped_segment?(segment)
        segment.match?(HOST_SHAPED_SEGMENT) && !segment.match?(FILE_EXTENSION_SEGMENT)
      end

      def trusted_post_context?(limit)
        return false if limit <= 0

        content_segments = SEGMENT_SETS.fetch(:content)
        context_segments = SEGMENT_SETS.fetch(:deep_post_context)

        (0...limit).any? do |i|
          segment = segments[i]
          content_segments.include?(segment) ||
            segment.match?(PathClassifier::YEARISH_SEGMENT) ||
            context_segments.include?(segment)
        end
      end

      def included_last_segment?
        !excluded_last_segment? && slug_last_segment?
      end

      def excluded_last_segment?
        last = segments.last
        high_confidence_junk_segment?(last) || SEGMENT_SETS[:vanity].include?(last)
      end

      def slug_last_segment?
        last = segments.last
        last.match?(YEARISH_SEGMENT) || last.match?(POST_SLUG_SEGMENT)
      end
    end
  end
end
