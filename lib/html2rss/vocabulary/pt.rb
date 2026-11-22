# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Portuguese (Brazilian and European spellings). It shares words with Spanish (+sobre+, +tema+, +entrada+),
    # which stay ambiguous here too, and the international +plus+.
    Pt = Language.new(
      code: :pt,
      terms: {
        path_section: %w[noticias notícias artigos publicacoes publicações postagens novidades entradas],
        path_article: %w[noticia notícia artigo publicacao publicação postagem entrada],
        path_profile: %w[autor autora autores autoras jornalista jornalistas],
        path_office: %w[redacao redação],
        path_non_article: %w[palavrascruzadas horoscopo horóscopo obituario obituário obituarios obituários aovivo],
        path_taxonomy: %w[categoria categorias etiqueta etiquetas tema temas],
        path_vanity: %w[assine assinar plus],
        path_soft_utility: %w[para-voce para-você recomendado planos plus],
        path_chrome: %w[
          sobre sobre-nos quem-somos contato contacto arquivo arquivos buscar busca ajuda entrar cadastro login
          perfil privacidade termos
        ],
        path_media: %w[vídeo vídeos video videos áudio audio podcast podcasts],
        path_deep_post_context: %w[imprensa sala-de-imprensa comunicados-de-imprensa],
        type_marker: ['vídeo', 'áudio', 'galeria', 'ao vivo', 'comunicado de imprensa', 'episódio completo'],
        utility_prefix: [
          'ver tudo', 'ver todos', 'todas as notícias', 'todas as noticias', 'assinar', 'assine', 'newsletter',
          'junte-se', 'plus'
        ],
        utility: [
          'sobre', 'sobre nós', 'sobre nos', 'contacto', 'contato', 'comentário', 'comentários', 'junte-se',
          'iniciar sessão', 'iniciar sessao', 'login', 'ver tudo', 'compartilhar', 'partilhar', 'registar-se',
          'cadastre-se', 'assinar', 'assine', 'newsletter', 'plus'
        ],
        recommended: ['recomendado', 'recomendado para você', 'recomendado para voce', 'recomendado para si'],
        utility_cta: [
          'assine a nossa', 'assine nossa', 'assine já', 'inscreva-se na', 'inscreva-se no', 'inscreva-se para',
          'cadastre-se para', 'compartilhe este', 'compartilhe esta', 'partilhe este', 'partilhe esta',
          'faça login para', 'faca login para', 'entre em contato', 'entre em contacto', 'fale conosco',
          'junte-se a nós', 'junte-se a nos', 'junte-se à nossa', 'junte-se ao nosso', 'deixe um comentário',
          'deixe um comentario'
        ],
        read_more: [
          'leia mais', 'ler mais', 'continue lendo', 'continuar a ler', 'saiba mais', 'veja mais', 'ver mais',
          /mais\s+informa(?:ç|c)(?:õ|o)es/, /leia\s+a\s+mat(?:é|e)ria\s+completa/,
          /leia\s+(?:o\s+)?(?:artigo|texto)\s+completo/
        ],
        topic_lead: ['mais'],
        topic_preposition: ['sobre', 'acerca de'],
        read_more_suffix: NONE,
        new_window_notice: [/abre\s+(?:em\s+(?:uma\s+)?|numa\s+|num\s+)nov[ao]\s+(?:janela|aba|separador)/],
        paid_label: [
          /(?:conte(?:ú|u)do\s+)?patrocinado(?:\s+por(?:\s+\S+){0,5})?/, 'publieditorial',
          /conte(?:ú|u)do\s+(?:de\s+)?parceir[oa]s?/
        ],
        ad_word: %w[publicidade anúncio anuncio],
        field_label: [
          /se(?:ç|c)(?:ã|a)o/, /sec(?:ç|c)(?:ã|a)o/, 'editoria', 'categoria', 'tema', 'assunto', 'artigo'
        ],
        type_label: ['tipo de artigo', /tipo\s+de\s+conte(?:ú|u)do/],
        pager_label: [/paginação(?!\p{L})/, /paginacao(?!\p{L})/],
        page_link: NONE,
        page_link_label: [
          /(?:p(?:á|a)gina\s+)?(?:anterior|seguinte)/, /pr(?:ó|o)xim[ao](?:\s+p(?:á|a)gina)?/,
          /mais\s+(?:antig[oa]s?|recentes?)/
        ],
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[sobre comentário comentários plus],
        path_section: %w[entradas],
        path_article: %w[entrada],
        path_taxonomy: %w[tema temas],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[sobre]
      }.freeze
    )
  end
end
