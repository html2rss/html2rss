# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Shared link-level heuristics used by scraper-local selection and
      # scoring. This keeps normalization and route/text classification
      # consistent without moving scraper policy into higher orchestration.
      class LinkHeuristics
        # Normalized URL plus reusable route-classification facts for one link.
        DestinationFacts = Data.define(
          :url,
          :destination,
          :segments,
          :content_path,
          :utility_path,
          :taxonomy_path,
          :vanity_path,
          :shallow,
          :strong_post_suffix,
          :high_confidence_junk_path,
          :high_confidence_utility_destination
        ) do
          # @param url [Html2rss::Url] normalized destination URL
          # @return [DestinationFacts] route facts for downstream link scoring
          def self.build(url)
            classifier = PathClassifier.new(url.path_segments)

            new(
              url:,
              destination: url.to_s,
              **classifier.destination_attributes
            )
          end
        end

        # Extracts a normalized href from a Nokogiri anchor or raw href value.
        class HrefExtractor
          # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
          # @return [String, nil] href without fragment, or nil when blank
          def self.call(anchor_or_href) = new(anchor_or_href).call

          # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
          def initialize(anchor_or_href)
            @anchor_or_href = anchor_or_href
          end

          # @return [String, nil] href without fragment, or nil when blank
          def call
            raw_href.to_s.split('#', 2).first.to_s.strip.then do |href|
              href unless href.empty?
            end
          end

          private

          def raw_href
            case @anchor_or_href
            when Nokogiri::XML::Node
              @anchor_or_href['href']
            else
              @anchor_or_href
            end
          end
        end

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

        # Classifies normalized destination path segments for scoring.
        # rubocop:disable Metrics/ClassLength
        class PathClassifier
          attr_reader :segments

          # Segment groups used to classify article, taxonomy, utility, and vanity routes.
          SEGMENT_SETS = {
            content: %w[
              article articles blog blogs changelog changelogs insight insights
              launch launches news post posts release releases story stories update updates
              artikel beitrag beitraege nachrichten neuigkeiten aktuelles
              articulo articulos noticia noticias entrada entradas publicacion publicaciones
              actualite actualites nouvelle nouvelles
              teaser teasers card cards
            ].to_set.freeze,
            utility: %w[
              about account archive archives author authors category categories comment comments
              contact feedback help login logout newsletter newsletters notification notifications
              preference preferences profile register search settings share signup subscribe
              tag tags topic topics
              feed feeds comment-feed comments-feed
              recommended
              for-you
              privacy terms cookie cookies
              join member members membership plus premium plans pricing user users
              kategorie kategorien schlagwort schlagworte thema themen autor autoren archiv
              ueber-uns ueber ueberuns profil kontakt impressum suche hilfe anmelden registrieren
              konto registrierung anmeldung abonnieren abo datenschutz nutzungsbedingungen agb
              categoria categorias etiqueta etiquetas tema temas autores archivos
              sobre-nosotros sobre quienes-somos buscar busqueda ayuda entrar ingresar
              registrarse registro cuenta suscribirse boletin privacidad condiciones
              categorie etiquette etiquettes sujet sujets theme themes auteur auteurs
              a-propos apropos recherche rechercher aide connexion s-inscrire
              sinscrire inscription compte s-abonner saboner lettre-information confidentialite mentions-legales cgu
              menu sidebar widget social modal popup banner promo ad ads
              related recommendation recommendations pagination pager
            ].to_set.freeze,
            high_confidence_junk: %w[
              about account archive archives author authors category categories comment comments
              contact cookie cookies feedback feed feeds help login logout notification notifications
              preference preferences privacy profile register search settings share signup subscribe
              tag tags terms topic topics comment-feed comments-feed user users
              kategorie kategorien schlagwort schlagworte thema themen autor autoren archiv
              ueber-uns ueber ueberuns profil kontakt impressum suche hilfe anmelden registrieren
              konto registrierung anmeldung abonnieren abo datenschutz nutzungsbedingungen agb
              categoria categorias etiqueta etiquetas tema temas autores archivos
              sobre-nosotros sobre quienes-somos buscar busqueda ayuda entrar ingresar
              registrarse registro cuenta suscribirse boletin privacidad condiciones
              categorie etiquette etiquettes sujet sujets theme themes auteur auteurs
              a-propos apropos recherche rechercher aide connexion s-inscrire
              sinscrire inscription compte s-abonner saboner lettre-information confidentialite mentions-legales cgu
              menu sidebar widget social modal popup banner promo ad ads
              related recommendation recommendations pagination pager
            ].to_set.freeze,
            taxonomy: %w[
              category categories tag tags topic topics
              kategorie kategorien schlagwort schlagworte thema themen
              categoria categorias etiqueta etiquetas tema temas
              categorie etiquette etiquettes sujet sujets theme themes
            ].to_set.freeze,
            vanity: %w[
              join membership plus premium pricing plans subscribe signup
              abonnieren abo
              suscribirse boletin
              s-abonner saboner
            ].to_set.freeze,
            deep_post_context: %w[
              press newsroom
              presse pressemitteilungen
              prensa
            ].to_set.freeze
          }.freeze
          # Path segment that begins with a year-like publishing marker.
          YEARISH_SEGMENT = /\A\d{4,}[\w-]*\z/
          # Hyphenated slug shape common to article permalinks.
          POST_SLUG_SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+){2,}\z/i

          # @param segments [Array<String>] normalized URL path segments
          def initialize(segments)
            @segments = segments
          end

          # @return [Hash] destination attributes consumed by DestinationFacts
          def destination_attributes
            route_attributes.merge(confidence_attributes)
          end

          # @return [Hash] baseline path classification attributes
          def route_attributes
            {
              segments:,
              content_path: content_path?,
              utility_path: utility_path?,
              taxonomy_path: taxonomy_path?,
              vanity_path: vanity_path?,
              shallow: shallow?,
              strong_post_suffix: strong_post_suffix?
            }
          end

          # @return [Hash] high-confidence noise classification attributes
          def confidence_attributes
            ConfidenceClassifier.new(self).attributes
          end

          # @return [Boolean] true when the route has article-like path evidence
          def content_path?
            @content_path ||= SEGMENT_SETS.fetch(:content).intersect?(segments.to_set) ||
                              yearish_content_context?
          end

          # @return [Boolean] true when the route includes utility/navigation evidence
          def utility_path?
            @utility_path ||= SEGMENT_SETS.fetch(:utility).intersect?(segments.to_set)
          end

          # @return [Boolean] true when the route points at conversion or account chrome
          def vanity_path?
            @vanity_path ||= SEGMENT_SETS.fetch(:vanity).intersect?(segments.to_set)
          end

          # @return [Boolean] true when the route points at taxonomy/listing chrome
          def taxonomy_path?
            @taxonomy_path ||= SEGMENT_SETS.fetch(:taxonomy).intersect?(segments.to_set)
          end

          # @return [Boolean] true when the route is too shallow to strongly indicate an article
          def shallow?
            segment_count = segments.size
            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)

            segment_count <= 1 || (segment_count == 2 && junk_segments.include?(segments.last))
          end

          # @return [Boolean] true when the final path segment looks like a post slug
          def strong_post_suffix?
            PostSuffixClassifier.new(segments).strong?
          end

          def utility_only_route?
            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)

            segments.all? { |segment| junk_segments.include?(segment) }
          end

          def shallow_high_confidence_route?
            junk_segments = SEGMENT_SETS.fetch(:high_confidence_junk)
            vanity_segments = SEGMENT_SETS.fetch(:vanity)

            shallow? && segments.any? do |segment|
              junk_segments.include?(segment) || vanity_segments.include?(segment)
            end
          end

          def deep_utility_context_route?
            LeadingSegments.new(segments).all_junk?
          end

          private

          def yearish_content_context?
            segments.any? { |segment| segment.match?(YEARISH_SEGMENT) } &&
              (strong_post_suffix? || LeadingSegments.new(segments).trusted_post_context?)
          end
        end
        # rubocop:enable Metrics/ClassLength

        # Classifies high-confidence junk and utility routes from path facts.
        class ConfidenceClassifier
          # @param path [PathClassifier] classified destination path
          def initialize(path)
            @path = path
          end

          # @return [Hash] high-confidence route classification attributes
          def attributes
            {
              high_confidence_junk_path: junk_path?,
              high_confidence_utility_destination: utility_destination?
            }
          end

          private

          def junk_path?
            return false if excluded_content_route?

            @path.taxonomy_path? ||
              @path.utility_only_route? ||
              @path.deep_utility_context_route? ||
              @path.shallow_high_confidence_route?
          end

          def utility_destination?
            return false if excluded_content_route?

            @path.vanity_path? || utility_route?
          end

          def excluded_content_route?
            @path.segments.empty? || @path.content_path? || @path.strong_post_suffix?
          end

          def utility_route?
            @path.taxonomy_path? ||
              @path.utility_only_route? ||
              @path.deep_utility_context_route? ||
              shallow_utility_route?
          end

          def shallow_utility_route?
            @path.shallow? && @path.utility_path?
          end
        end

        # Classifies route context before the final segment.
        class LeadingSegments
          # @param segments [Array<String>] normalized URL path segments
          def initialize(segments)
            @segments = segments[0...-1]
          end

          # @return [Boolean] true when every leading segment is utility chrome
          def all_junk?
            junk_segments = PathClassifier::SEGMENT_SETS.fetch(:high_confidence_junk)

            @segments.any? && @segments.all? { |segment| junk_segments.include?(segment) }
          end

          # @return [Boolean] true when leading segments provide article context
          def trusted_post_context?
            content_segments = PathClassifier::SEGMENT_SETS.fetch(:content)
            context_segments = PathClassifier::SEGMENT_SETS.fetch(:deep_post_context)

            @segments.any? do |segment|
              content_segments.include?(segment) ||
                segment.match?(PathClassifier::YEARISH_SEGMENT) ||
                context_segments.include?(segment)
            end
          end
        end

        # Classifies whether the final segment is a strong post-like suffix.
        class PostSuffixClassifier
          # @param segments [Array<String>] normalized URL path segments
          def initialize(segments)
            @segments = segments
          end

          # @return [Boolean] true when the final path segment looks like a post slug
          def strong?
            @segments.any? &&
              included_last_segment? &&
              LeadingSegments.new(@segments).trusted_post_context?
          end

          private

          def included_last_segment?
            !excluded_last_segment? && slug_last_segment?
          end

          def excluded_last_segment?
            excluded_segments.any? { |segment| segment.include?(last_segment) }
          end

          def excluded_segments
            [
              PathClassifier::SEGMENT_SETS.fetch(:high_confidence_junk),
              PathClassifier::SEGMENT_SETS.fetch(:vanity)
            ]
          end

          def slug_last_segment?
            last_segment.match?(PathClassifier::YEARISH_SEGMENT) ||
              last_segment.match?(PathClassifier::POST_SLUG_SEGMENT)
          end

          def last_segment
            @segments.last
          end
        end

        # @param base_url [String, Html2rss::Url] page URL used to resolve relative hrefs
        def initialize(base_url)
          @base_url = base_url
          @text_classifier = TextClassifier.new
        end

        # Builds normalized destination facts for an anchor element or href string.
        #
        # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
        # @return [DestinationFacts, nil] normalized destination facts, or nil for blank/invalid URLs
        def destination_facts(anchor_or_href)
          href = HrefExtractor.call(anchor_or_href)
          return unless href

          url = Html2rss::Url.from_relative(href, @base_url)
          DestinationFacts.build(url)
        rescue ArgumentError
          nil
        end

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text matches a utility label
        def utility_text?(text) = @text_classifier.utility?(text)

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text begins with a utility label
        def utility_prefix_text?(text) = @text_classifier.utility_prefix?(text)

        # @param text [String, #to_s] visible anchor text
        # @return [Boolean] true when text identifies recommendation chrome
        def recommended_text?(text) = @text_classifier.recommended?(text)
      end
    end
  end
end
