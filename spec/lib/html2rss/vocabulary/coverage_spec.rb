# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/SpecFilePathFormat

# Every language's path words are read by the concept's consumer on a page in that language, and the text
# concepts the languages gained are read as labels.
RSpec.describe Html2rss::Vocabulary do
  let(:path) do
    lambda do |lang, segments|
      Html2rss::LinkDestination::PathClassifier.new(segments, vocabulary: described_class[lang])
    end
  end
  let(:text) { ->(lang) { Html2rss::LinkDestination::TextClassifier.new(vocabulary: described_class[lang]) } }
  # Each way of reading a word concept: a classifier call on the term inside a short path.
  let(:path_readers) do
    {
      path_section: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).content_path? },
      path_article: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).content_path? },
      path_profile: ->(lang, term) { path.call(lang, [term, 'maria-silva']).non_article_path? },
      path_office: ->(lang, term) { path.call(lang, [term, 'maria']).non_article_path? },
      path_non_article: ->(lang, term) { path.call(lang, [term, 'abc']).non_article_path? },
      path_taxonomy: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).taxonomy_path? },
      path_vanity: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).vanity_path? },
      path_soft_utility: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).utility_path? },
      path_chrome: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).utility_path? },
      path_media: ->(lang, term) { path.call(lang, [term, 'harbor-ferry-schedule']).media_path? },
      path_deep_post_context: lambda { |lang, term|
        path.call(lang, [term, 'harbor-ferry-schedule-update']).strong_post_suffix?
      }
    }
  end

  describe 'path words' do
    it 'are read on a page in their own language, for every language and every word concept',
       :aggregate_failures do
      described_class::ALL.each do |language|
        path_readers.each do |concept, reader|
          language.terms.fetch(concept).each do |term|
            expect(reader.call(language.code, term)).to be(true), "#{language.code} #{concept} #{term.inspect}"
          end
        end
      end
    end

    it 'leaves a slug without such a word as it was', :aggregate_failures do
      described_class::ALL.each do |language|
        expect(path_readers.fetch(:path_media).call(language.code, 'harbor')).to be(false)
        expect(path_readers.fetch(:path_non_article).call(language.code, 'harbor')).to be(false)
        expect(path_readers.fetch(:path_deep_post_context).call(language.code, 'harbor')).to be(false)
      end
    end
  end

  describe 'Portuguese labels' do
    it 'reads utility, recommended and read-more labels', :aggregate_failures do
      pt = text.call(:pt)

      ['Ver tudo', 'Sobre nós', 'Iniciar sessão', 'Cadastre-se', 'Comentários'].each do |label|
        expect(pt.utility?(label)).to be(true), label
      end
      ['Assine já', 'Ver todos os vídeos'].each { expect(pt.utility_prefix?(_1)).to be(true) }
      expect(pt.recommended?('Recomendado para você')).to be(true)
      ['Leia mais', 'Saiba mais', 'Mais sobre «O porto da cidade»', 'Leia mais (abre em nova aba)',
       'Leia a matéria completa'].each { expect(pt.read_more?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a chrome word a headline', :aggregate_failures do
      pt = text.call(:pt)

      expect(pt.utility?('Comentário do dia: o porto reabre')).to be(true)
      expect(text.call(:en).utility?('Comentário do dia: o porto reabre')).to be(false)
      expect(pt.read_more?('Leia mais sobre o porto da cidade')).to be(false)
    end

    it 'reads sponsorship labels and a section label', :aggregate_failures do
      kind = Html2rss::LinkDestination::Sponsorship::LabelText.method(:kind)

      expect(kind.call('Conteúdo patrocinado por Marca')).to eq(:paid_label)
      expect(kind.call('Publieditorial')).to eq(:paid_label)
      expect(kind.call('Publicidade')).to eq(:label)
      title = Html2rss::Article::Title.compose('Porto reabre', kicker: 'Seção: Transportes')

      expect(title).to eq('Transportes: Porto reabre')
    end
  end

  describe 'pager nouns' do
    let(:pager) do
      lambda do |label|
        element = Nokogiri::HTML("<html><body><nav aria-label=\"#{label}\"></nav></body></html>").at('nav')
        Html2rss::SST::Tags.chrome_scope(element, :sectioned) == :chrome
      end
    end

    it 'reads the French and Japanese nouns as pagination chrome', :aggregate_failures do
      ['Pagination', 'Navigation des pages', 'ページネーション', 'ページ送り', 'Paginação'].each do |label|
        expect(pager.call(label)).to be(true), label
      end
      expect(pager.call('Paginated stories')).to be(false)
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/SpecFilePathFormat
