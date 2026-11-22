# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Spanish.
    Es = Language.new(
      code: :es,
      terms: {
        path_section: %w[articulos noticias entradas publicaciones],
        path_article: %w[articulo noticia entrada publicacion],
        path_profile: %w[autores periodista periodistas],
        path_office: %w[redaccion redacción],
        path_non_article: %w[juegos crucigrama crucigramas horoscopo horoscopos esquelas obituarios envivo],
        path_taxonomy: %w[categoria categorias etiqueta etiquetas tema temas],
        path_vanity: %w[suscribirse boletin plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[
          autores archivos sobre-nosotros sobre quienes-somos buscar busqueda ayuda entrar ingresar registrarse
          registro cuenta suscribirse boletin privacidad condiciones
        ],
        path_media: %w[vídeo vídeos],
        path_deep_post_context: %w[prensa],
        type_marker: ['vídeo', 'galería', 'en directo', 'nota de prensa', 'episodio completo'],
        utility_prefix: [
          'ver todos', 'ver todo', 'todas las noticias', 'suscribirse', 'boletin', 'boletín', 'comentarios feed',
          'unirse', 'plus'
        ],
        utility: [
          'sobre', 'sobre nosotros', 'contacto', 'comentario', 'comentarios', 'unirse', 'iniciar sesion', 'login',
          'miembro', 'membresia', 'membresía', 'ver todo', 'compartir', 'registrarse', 'suscribirse', 'boletin',
          'boletín', 'plus'
        ],
        recommended: ['recomendado', 'recomendado para ti'],
        utility_cta: [
          'suscríbete a', 'suscribete a', 'suscríbase a',
          /compartir\s+este\s+art(?:í|i)culo(?=[\s\p{P}\p{S}]*\z|\s+con\s)/,
          'inicia sesión para', 'inicia sesion para',
          /iniciar\s+sesi(?:ó|o)n\s+para\s+(?:comentar|ver|leer|acceder|continuar|seguir)/,
          'regístrate para', 'registrate para', 'contáctanos', 'contactanos', 'contacta con nosotros',
          'únete a nuestra', 'unete a nuestra', 'deja un comentario', /dejar\s+un\s+comentario(?=[\s\p{P}\p{S}]*\z)/
        ],
        read_more: [
          /leer\s+m(?:á|a)s/, 'seguir leyendo', 'continuar leyendo', /saber\s+m(?:á|a)s/,
          /m(?:á|a)s\s+informaci(?:ó|o)n/, /leer\s+(?:todo|el\s+art(?:í|i)culo\s+completo)/
        ],
        topic_lead: [/m(?:á|a)s/],
        topic_preposition: ['sobre'],
        read_more_suffix: NONE,
        new_window_notice: [/se\s+abre\s+en\s+(?:una\s+)?nueva\s+(?:ventana|pesta(?:ñ|n)a)/],
        paid_label: [/(?:contenido\s+)?patrocinado(?:\s+por(?:\s+\S+){0,5})?/, 'publirreportaje'],
        ad_word: %w[publicidad],
        field_label: [/secci(?:ó|o)n/, /categor(?:í|i)a/, 'tema', /art(?:í|i)culo/],
        type_label: [/tipo\s+de\s+art(?:í|i)culo/, 'tipo de contenido'],
        pager_label: [/paginación(?!\p{L})/, /paginacion(?!\p{L})/],
        page_link: NONE,
        page_link_label: [
          /(?:p(?:á|a)gina\s+)?(?:anterior|siguiente)/, /m(?:á|a)s\s+(?:antiguos?|recientes?)/,
          /(?:entradas\s+)?(?:anteriores|siguientes)/
        ],
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: %w[episodio],
        podcast_unspaced: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[sobre plus],
        path_chrome: %w[sobre],
        path_taxonomy: %w[tema temas],
        path_section: %w[entradas],
        path_article: %w[entrada],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
