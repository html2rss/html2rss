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

  describe 'Russian labels' do
    let(:ru) { text.call(:ru) }
    # Every predicate that would drop a headline: a label read as a whole text or a prefix, a recommendation, a
    # read-more phrase, and Cleanup's junk reason.
    let(:readers) do
      {
        utility: ->(label) { ru.utility?(label) }, chrome: ->(label) { ru.utility_chrome?(label) },
        prefix: ->(label) { ru.utility_prefix?(label) }, recommended: ->(label) { ru.recommended?(label) },
        read_more: ->(label) { ru.read_more?(label) }, junk: ->(label) { !Html2rss::AutoSource::Cleanup.junk_reason(label).nil? }
      }
    end

    it 'reads utility labels, whatever their case, with a trailing word or a count', :aggregate_failures do
      ['О нас', 'О КОМПАНИИ', 'контакты', 'Обратная связь', 'Войти', 'Зарегистрироваться', 'Поделиться',
       'Подписаться', 'Смотреть всё', 'Смотреть все', 'Показать все', 'Контакты (3)', '[Войти]'].each do |label|
        expect(ru.utility_chrome?(label)).to be(true), label
      end
      ['Подписаться', 'Смотреть всё', 'Показать все'].each { expect(ru.utility?(_1)).to be(true), _1 }
      ['Подпишитесь на рассылку', 'Подписывайтесь на наш канал'].each { expect(ru.utility_prefix?(_1)).to be(true), _1 }
    end

    it 'reads call-to-action openers, and the infinitive only as a whole label', :aggregate_failures do
      ['Свяжитесь с нами', 'Оставьте комментарий', 'Войдите, чтобы комментировать', 'Присоединяйтесь к нам',
       'Оставить комментарий'].each { expect(ru.utility_chrome?(_1)).to be(true), _1 }
      expect(ru.utility_chrome?('Оставить комментарий к проекту бюджета')).to be(false)
    end

    it 'reads recommendation and read-more labels, with the ё and е spellings', :aggregate_failures do
      ['Вам может понравиться', 'Рекомендуем почитать', 'Рекомендуем прочитать'].each do |label|
        expect(ru.recommended?(label)).to be(true), label
      end
      ['Читать далее', 'Читать ещё', 'Читать еще', 'ЧИТАТЬ ЕЩЁ', 'Читать всё', 'Читать все', 'Подробнее', 'ПОДРОБНЕЕ',
       'Подробности', 'Узнать больше', 'Подробнее на тему «Налоги»', 'Читать далее (открывается в новой вкладке)',
       'Читать далее (откроется в новом окне)'].each do |label|
        expect(ru.read_more?(label)).to be(true), label
        expect(Html2rss::AutoSource::Cleanup.junk_reason(label)).to eq(:cta), label
      end
    end

    it 'keeps a headline a headline in every predicate that could drop it', :aggregate_failures do
      ['Все новости недели: итоги', 'Подробнее о новом законе вступившем в силу', 'Больше о налогах в России',
       'Ещё о выборах в Думу',
       'Рекомендованное Минздравом лекарство оказалось неэффективным', 'Рекомендуем не пользоваться старыми картами',
       'Комментарии к закону обсудили в Думе', 'Комментарий Пескова', 'Регистрация новых партий продлится месяц',
       'Подписка на газету подорожала', 'Рассылка писем из банка выросла', 'Вход в метро станет бесплатным',
       'Вход закрыт', 'Тема дня: налоги', 'Эпизод со стрельбой на рынке',
       'Читать ещё: итоги дня в Думе'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'reads a two-word headline that opens with a chrome label as that label (a known limitation)',
       :aggregate_failures do
      expect(ru.utility_chrome?('Контакты Пескова')).to be(true)
      expect(ru.utility_chrome?('О нас забыли')).to be(true)
      expect(ru.utility_chrome?('Контакты России и Китая обсудили новый договор')).to be(false)
    end

    it 'reads a headline that opens with a verb or label as a loose utility prefix (vanity paths only)',
       :aggregate_failures do
      ['Войти в историю: как строили мост', 'Подписаться на санкции не готовы',
       'Контакты России и Китая обсудили новый договор'].each do |headline|
        expect(ru.utility?(headline)).to be(true), headline
        expect(readers.except(:utility).transform_values { _1.call(headline) }.values).to all(be(false)), headline
      end
    end

    it 'reads sponsorship labels with the ё and е spellings, and an ad word as a whole text', :aggregate_failures do
      kind = Html2rss::LinkDestination::Sponsorship::LabelText.method(:kind)

      ['На правах рекламы', 'Партнёрский материал', 'ПАРТНЕРСКИЙ МАТЕРИАЛ', 'Партнёрские материалы',
       'Материал партнера', 'Материал партнёра', 'Спонсорский материал', 'Рекламный материал'].each do |label|
        expect(kind.call(label)).to eq(:paid_label), label
      end
      expect(kind.call('Реклама')).to eq(:label)
      expect(kind.call('Реклама на ТВ выросла в этом году')).to be_nil
    end

    it 'reads kicker noise: a field label, a type marker, a clock with its time zone', :aggregate_failures do
      title = Html2rss::Article::Title
      noise = ->(piece) { title.noise_piece?(piece, vocabulary: described_class[:ru]) }

      ['Раздел:', 'Тема :', 'Тип материала: Видео', 'Видео', 'ВИДЕО', 'Прямой эфир', 'Фотогалерея'].each do |piece|
        expect(noise.call(piece)).to be(true), piece
      end
      expect(noise.call('Тема дня')).to be(false)
      expect(title.compose('Порт открыт после ремонта', kicker: 'Раздел: Транспорт'))
        .to eq('Транспорт: Порт открыт после ремонта')
      expect(title.compose('Порт открыт после ремонта', kicker: '10:30 мск')).to eq('Порт открыт после ремонта')
    end

    it 'reads a Cyrillic podcast word with a letter boundary, in any case', :aggregate_failures do
      hint = Html2rss::Syndication::Discovery::PODCAST_PAGE_HINT

      podcast = ['Подкаст о портовом городе', 'Все подкасты радио', 'выпуск ПОДКАСТОВ']

      expect(podcast).to all(match(hint))
      ['Подкастинг как профессия', 'Эпизод со стрельбой на рынке', 'Мегаподкаст'].each { expect(_1).not_to match(hint) }
    end

    it 'reads Cyrillic path words, percent-encoded or not', :aggregate_failures do
      encoded = Html2rss::Url.from_absolute('https://example.com/%D0%B2%D0%B8%D0%B4%D0%B5%D0%BE/harbor-ferry-schedule')
      classifier = Html2rss::LinkDestination::PathClassifier.new(encoded.decoded_path_segments,
                                                                 vocabulary: described_class[:ru])

      expect(classifier.media_path?).to be(true)
      expect(path.call(:ru, %w[Видео harbor-ferry-schedule]).media_path?).to be(true)
      expect(path.call(:ru, %w[помощь harbor-ferry-schedule]).utility_path?).to be(true)
      expect(path.call(:ru, %w[пресс-релизы harbor-ferry-schedule-update]).strong_post_suffix?).to be(true)
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

    it 'reads the Russian nouns as pagination chrome, and a Russian previous or next as a page link',
       :aggregate_failures do
      ['Пагинация', 'ПАГИНАЦИЯ списка', 'Навигация по страницам', 'Постраничная навигация'].each do |label|
        expect(pager.call(label)).to be(true), label
      end
      expect(pager.call('Пагинацией занимается мэрия')).to be(false)
      {
        'Предыдущая страница' => true, 'Следующая' => true, 'Далее' => true, 'Назад' => true, 'Вперёд' => true,
        'Вперед' => true, 'Более ранние' => true, 'Следующая новость' => true, 'Далее по теме порта' => false,
        'Назад в будущее' => false
      }.each do |label, chrome|
        link = %(<a href="/a">#{label}</a>)
        markup = %(<html><body><main><ul class="pagination"><li>#{link}</li></ul></main></body></html>)
        doc = Html2rss::SST::Normalizer.call(markup)

        expect(doc.index.ignored_chrome?(doc.root.find { _1.name == :main }.children.first)).to be(chrome), label
      end
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/SpecFilePathFormat
