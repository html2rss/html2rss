# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat

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
      kind = ->(text) { Html2rss::LinkDestination::Sponsorship::LabelText.kind(text, vocabulary: described_class[:all]) }

      expect(kind.call('Conteúdo patrocinado por Marca')).to eq(:paid_label)
      expect(kind.call('Publieditorial')).to eq(:paid_label)
      expect(kind.call('Publicidade')).to eq(:label)
      title = Html2rss::Article::Title.compose('Porto reabre', kicker: 'Seção: Transportes', vocabulary: all_scope)

      expect(title).to eq('Transportes: Porto reabre')
    end
  end

  describe 'Russian labels' do
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:ru]) } }
    let(:ru) { text.call(:ru) }
    # Every predicate that would drop a headline: a label read as a whole text or a prefix, a recommendation, a
    # read-more phrase, and Cleanup's junk reason.
    let(:readers) do
      {
        utility: ->(label) { ru.utility?(label) }, chrome: ->(label) { ru.utility_chrome?(label) },
        prefix: ->(label) { ru.utility_prefix?(label) }, recommended: ->(label) { ru.recommended?(label) },
        read_more: ->(label) { ru.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
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
        expect(junk_reason.call(label)).to eq(:cta), label
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
      kind = ->(text) { Html2rss::LinkDestination::Sponsorship::LabelText.kind(text, vocabulary: described_class[:all]) }

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
      expect(title.compose('Порт открыт после ремонта', kicker: 'Раздел: Транспорт', vocabulary: all_scope))
        .to eq('Транспорт: Порт открыт после ремонта')
      expect(title.compose('Порт открыт после ремонта', kicker: '10:30 мск',
                                                        vocabulary: all_scope)).to eq('Порт открыт после ремонта')
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

  describe 'Chinese labels' do
    let(:labels) do
      %w[关于我们 關於我們 联系我们 聯絡我們 登录 登入 注册 註冊 订阅 訂閱 分享 搜索 搜尋 隐私政策
         隱私權政策 评论 留言 帮助 幫助]
    end
    let(:zh) { text.call(:zh) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:zh]) } }
    # Every predicate that would drop a headline (see the Russian labels).
    let(:readers) do
      {
        utility: ->(label) { zh.utility?(label) }, chrome: ->(label) { zh.utility_chrome?(label) },
        prefix: ->(label) { zh.utility_prefix?(label) }, recommended: ->(label) { zh.recommended?(label) },
        read_more: ->(label) { zh.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads Simplified and Traditional chrome labels as whole labels', :aggregate_failures do
      labels.each { expect(zh.utility_chrome?(_1)).to be(true), _1 }
      ['登录 (3)', '[订阅]', '→ 订阅 →', '订阅 (12)'].each { expect(zh.utility_chrome?(_1)).to be(true), _1 }
      %w[推荐阅读 推薦閱讀 相关阅读 相關閱讀 猜你喜欢 猜你喜歡].each { expect(zh.recommended?(_1)).to be(true), _1 }
    end

    it 'reads a bracketed count after a Chinese label as chrome, a bare number as a headline', :aggregate_failures do
      expect(['评论 (12)', '相关阅读 [3]', '隐私政策 （2）'].map { zh.utility_chrome?(_1) }).to all(be(true))
      expect(['评论 12', '相关阅读 3', '隐私政策 2'].map { zh.utility_chrome?(_1) }).to all(be(false))
    end

    it 'reads Chinese read-more and call-to-action labels as whole labels, as chrome and junk', :aggregate_failures do
      %w[阅读全文 閱讀全文 了解更多 瞭解更多 继续阅读 繼續閱讀 查看全文].each do |label|
        expect([zh.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      %w[订阅电子报 訂閱我們的電子報 立即订阅 免費訂閱].each { expect(zh.utility_chrome?(_1)).to be(true), _1 }
      ['→ 阅读全文 →', '[了解更多]'].each { expect(zh.read_more?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a read-more or call-to-action word a headline', :aggregate_failures do
      %w[阅读全文的人数创新高 了解更多国家的经验 继续阅读文章会发现 立即订阅用户突破百万 免费订阅制即将结束
         阅读全文需要付费吗].each do |headline|
        expect([zh.read_more?(headline), zh.utility_chrome?(headline), junk_reason.call(headline)])
          .to eq([false, false, nil]), headline
      end
    end

    it 'reads those labels on a Chinese page only', :aggregate_failures do
      [nil, :ja, :en, 'ja-JP'].each do |lang|
        expect(text.call(lang).read_more?('阅读全文')).to be(false), lang.inspect
        expect(text.call(lang).utility_chrome?('立即订阅')).to be(false), lang.inspect
      end
    end

    it 'reads a Chinese label on a Chinese page only', :aggregate_failures do
      labels.product([nil, :ja, :en, :de, 'ja-JP']).each do |label, lang|
        expect(text.call(lang).utility_chrome?(label)).to be(false), "#{label} #{lang.inspect}"
        expect(text.call(lang).utility?(label)).to be(false), "#{label} #{lang.inspect}"
      end
      expect(text.call('zh-Hant').utility_chrome?('關於我們')).to be(true)
    end

    it 'keeps a headline that opens with a label word, with or without a space, a headline', :aggregate_failures do
      ['帮助 受灾群众重建家园', '幫助 受災民眾重建家園', '搜索 失联渔船行动持续第三天', '评论 美国大选结果影响全球市场',
       '更多 城市加入低碳行动计划', '分享 创业十年的失败经验', '注册 成功率 提升', '注册：新用户数量创新高',
       '注册、登录功能全面升级', '订阅，正在改变媒体行业', '订阅量创新高，公司股价上涨',
       '登录后发表评论的用户将获奖', '评论员表示今年经济向好', '注册制改革全面推进', '更多人选择乘坐地铁',
       '分享经济再度升温', '搜索引擎公司发布新产品', '關於我們的未來 專家這樣說', '联系我们的客服被投诉',
       '推荐阅读量破亿', '留言板上的故事', '发表评论：官方回应', '登入系統當機多地受影響', '評論：選舉結果',
       '直播间里的新规', '视频会议成主流', '独家：某公司将上市', '独自开发的软件', '推荐阅读 书目发布'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'reads the shared type markers, not 独自 and 写真, and no marker of its own', :aggregate_failures do
      title = Html2rss::Article::Title
      noise = ->(piece) { title.noise_piece?(piece, vocabulary: described_class[:zh]) }

      %w[速報 詳報 動画].each { expect(noise.call(_1)).to be(true), _1 }
      %w[独自 写真 快讯 快訊 独家 獨家 视频 視頻 圖集 直播 直播间].each { expect(noise.call(_1)).to be(false), _1 }
      expect(title.compose('港口重新开放', kicker: '独家', vocabulary: described_class[:zh])).to eq('独家: 港口重新开放')
      expect(title.compose('港口重新开放', kicker: '独自', vocabulary: described_class[:zh])).to eq('独自: 港口重新开放')
    end

    it 'does not read 播客 inside a Han compound as a podcast word', :aggregate_failures do
      hint = Html2rss::Syndication::Discovery::PODCAST_PAGE_HINT

      %w[直播客户端 主播客串 转播客场 港口播客].each { expect(hint.match?(_1)).to be(false), _1 }
    end
  end

  describe 'Korean labels' do
    let(:ko) { text.call(:ko) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:ko]) } }
    let(:readers) do
      {
        utility: ->(label) { ko.utility?(label) }, chrome: ->(label) { ko.utility_chrome?(label) },
        prefix: ->(label) { ko.utility_prefix?(label) }, recommended: ->(label) { ko.recommended?(label) },
        read_more: ->(label) { ko.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels', :aggregate_failures do
      %w[로그인 로그아웃 회원가입 검색 이용약관 개인정보처리방침 회사소개 사이트맵 고객센터 뉴스레터 구독 닫기 공유
         댓글].each { expect(ko.utility_chrome?(_1)).to be(true), _1 }
      ['개인정보 처리방침', '본문 바로가기', '로그인 (3)', '[닫기]', '→ 닫기 →'].each { expect(ko.utility_chrome?(_1)).to be(true), _1 }
      %w[관련기사 추천기사].push('관련 기사', '추천 기사').each { expect(ko.recommended?(_1)).to be(true), _1 }
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['기사 전문 보기', '자세히 보기', '전문보기', '계속 읽기'].each do |label|
        expect([ko.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['구독하기', '뉴스레터 구독하기', '지금 구독하기', '신문구독'].each { expect(ko.utility_chrome?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a label word, a particle or a space a headline', :aggregate_failures do
      ['로그인 오류로 서비스 중단', '구독 경제가 성장한다', '검색 시장 점유율 변화', '더보기 어려운 현실',
       '댓글 조작 의혹 수사 착수', '공유 오피스 입주율 상승', '닫기 어려운 계약서', '회원가입 절차 간소화 추진',
       '관련기사 삭제 요구 논란', '자세히 보기 어려운 통계의 함정'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year a headline, and a label with a short count chrome', :aggregate_failures do
      ['추천 기사 2026', '추천 뉴스 2026', '관련 기사 2026', '신문 구독 2026', '무료 구독 2026', '뉴스레터 구독 2026',
       '회사 소개 2026', '개인정보 처리방침 2026'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
      expect(['관련 기사 (3)', '관련 기사 [3]', '관련 기사 （3）', '관련 기사 ［3］'].map { ko.recommended?(_1) }).to all(be(true))
      expect(['관련 기사 3', '관련 기사 (3', '관련 기사 3)', '관련 기사 1234'].map { ko.recommended?(_1) }).to all(be(false))
    end

    it 'reads the labels on a Korean page only, and the new-window notice', :aggregate_failures do
      [nil, :ja, :en, :zh].each { expect(text.call(_1).utility_chrome?('로그인')).to be(false), _1.inspect }
      expect(ko.utility_chrome?('로그인 (새 창 열기)')).to be(true)
      expect(text.call(nil).utility_chrome?('로그인 (새 창 열기)')).to be(false)
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::Ko.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:ko].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Ukrainian labels' do
    let(:uk) { text.call(:uk) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:uk]) } }
    let(:readers) do
      {
        utility: ->(label) { uk.utility?(label) }, chrome: ->(label) { uk.utility_chrome?(label) },
        prefix: ->(label) { uk.utility_prefix?(label) }, recommended: ->(label) { uk.recommended?(label) },
        read_more: ->(label) { uk.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels', :aggregate_failures do
      %w[вхід увійти реєстрація пошук підписка підписатися поділитися закрити меню коментарі контакти].push(
        'про нас', 'про компанію', 'карта сайту', 'політика конфіденційності', 'умови використання',
        'Вхід (3)', '[Пошук]'
      ).each { expect(uk.utility_chrome?(_1)).to be(true), _1 }
      ['читайте також', 'Читайте також', 'схожі матеріали', 'рекомендовані матеріали', 'вас також може зацікавити']
        .each { expect(uk.recommended?(_1)).to be(true), _1 }
    end

    it 'reads the apostrophe spellings of a label alike', :aggregate_failures do
      ["'", '’', 'ʼ'].each do |mark|
        expect(uk.recommended?("пов#{mark}язані матеріали")).to be(true), mark
        expect(uk.utility_chrome?("зв#{mark}яжіться з нами")).to be(true), mark
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Читати далі', 'докладніше', 'Детальніше', 'дізнатися більше'].each do |label|
        expect([uk.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['підписатися на розсилку', 'Поділіться', 'залишити коментар']
        .each { expect(uk.utility_chrome?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a label noun a headline', :aggregate_failures do
      ['Пошук зниклих триває', 'Вхід до міста закрито', 'Реєстрація виборців завершилась', 'Підписка на газети зросла',
       'Контакти з сусідами рятують', 'Меню шкільних їдалень оновили', 'Коментарі експертів розділились',
       'Детальніше про реформу розповів міністр', 'Читати далі стане легше: бібліотеки оновили фонд',
       'Закрити кордон пропонують депутати'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps the bare phrase зворотний зв’язок a headline, with each apostrophe', :aggregate_failures do
      ["'", '’', 'ʼ'].each do |mark|
        readers.each { |name, reader| expect(reader.call("Зворотний зв#{mark}язок")).to be(false), "#{name}: #{mark}" }
      end
    end

    it 'keeps a label followed by a year a headline, and a label with a short count chrome', :aggregate_failures do
      ['Читайте також 2026', 'Рекомендовані матеріали 2026', 'Схожі новини 2026', 'Про нас 2026',
       'Політика конфіденційності 2026', 'Підписка 2026'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
      expect(uk.recommended?('Схожі матеріали (3)')).to be(true)
    end

    it 'keeps a label followed by a bare count a headline', :aggregate_failures do
      ['Умови використання 2', 'Політика конфіденційності: 100', 'Схожі матеріали 3'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'reads the labels on a Ukrainian page only, and the new-window notice', :aggregate_failures do
      [nil, :ru, :en, :ko].each { expect(text.call(_1).utility_chrome?('Вхід')).to be(false), _1.inspect }
      expect(uk.utility_chrome?('Вхід (відкриється у новому вікні)')).to be(true)
      expect(text.call(nil).utility_chrome?('Вхід (відкриється у новому вікні)')).to be(false)
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::Uk.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:uk].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Greek labels' do
    let(:el) { text.call(:el) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:el]) } }
    let(:readers) do
      {
        utility: ->(label) { el.utility?(label) }, chrome: ->(label) { el.utility_chrome?(label) },
        prefix: ->(label) { el.utility_prefix?(label) }, recommended: ->(label) { el.recommended?(label) },
        read_more: ->(label) { el.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, in any case', :aggregate_failures do
      %w[Σύνδεση ΣΥΝΔΕΣΗ ΣΎΝΔΕΣΗ Αποσύνδεση Εγγραφή ΕΓΓΡΑΦΗ Αναζήτηση ΑΝΑΖΗΤΗΣΗ Επικοινωνία Συνδρομή Σχόλια Μενού
         Εγγραφείτε].each { expect(el.utility_chrome?(_1)).to be(true), _1 }
      ['Όροι χρήσης', 'ΟΡΟΙ ΧΡΗΣΗΣ', 'ΌΡΟΙ ΧΡΉΣΗΣ', 'Πολιτική απορρήτου', 'ΠΟΛΙΤΙΚΗ ΑΠΟΡΡΗΤΟΥ', 'Σχετικά με εμάς',
       'ΟΡΟΙ ΚΑΙ ΠΡΟΫΠΟΘΕΣΕΙΣ', 'Όροι και προϋποθέσεις', 'Επικοινωνία (3)', '[Μενού]']
        .each { expect(el.utility_chrome?(_1)).to be(true), _1 }
      ['Σχετικά άρθρα', 'ΣΧΕΤΙΚΑ ΑΡΘΡΑ', 'Προτεινόμενα', 'Προτεινόμενα άρθρα', 'Διαβάστε επίσης', 'ΔΙΑΒΑΣΤΕ ΕΠΙΣΗΣ']
        .each { expect(el.recommended?(_1)).to be(true), _1 }
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Διαβάστε περισσότερα', 'ΔΙΑΒΑΣΤΕ ΠΕΡΙΣΣΟΤΕΡΑ', 'Περισσότερα', 'Διαβάστε ολόκληρο το άρθρο'].each do |label|
        expect([el.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Εγγραφή στο newsletter', 'ΕΓΓΡΑΦΗ ΣΤΟ NEWSLETTER', 'Κάντε συνδρομή', 'Γίνετε συνδρομητής']
        .each { expect(el.utility_chrome?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a label word a headline', :aggregate_failures do
      ['Αναζήτηση για τους αγνοούμενους', 'Σύνδεση του δικτύου με την Κρήτη', 'Εγγραφή μαθητών στα σχολεία',
       'Επικοινωνία με τους ορειβάτες διακόπηκε', 'Συνδρομή στα μέσα μεταφοράς ακριβαίνει',
       'Σχόλια του πρωθυπουργού για την οικονομία', 'Όροι χρήσης της γης αλλάζουν στα νησιά',
       'Περισσότερα έσοδα από τον τουρισμό φέτος', 'Σχετικά με την απεργία της Τρίτης δήλωσε ο υπουργός',
       'Διαβάστε επίσης ότι η τιμή του ρεύματος πέφτει'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a sports headline that echoes a dropped phrase a headline', :aggregate_failures do
      ['Πίσω στην κορυφή', 'Ο λογαριασμός μου'].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'keeps a label followed by a year a headline, and a label with a short count chrome', :aggregate_failures do
      ['Σχετικά άρθρα 2026', 'Προτεινόμενα άρθρα 2026', 'Διαβάστε επίσης 2026', 'Όροι χρήσης 2026',
       'Πολιτική απορρήτου 2026', 'Διαβάστε περισσότερα 2026', 'Κάντε συνδρομή 2026'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
      expect(el.recommended?('Σχετικά άρθρα 3')).to be(false)
      expect(el.recommended?('Σχετικά άρθρα (3)')).to be(true)
    end

    it 'reads the labels on a Greek page only, and the new-window notice', :aggregate_failures do
      [nil, :ja, :en, :ko].each { expect(text.call(_1).utility_chrome?('Επικοινωνία')).to be(false), _1.inspect }
      expect(el.utility_chrome?('Επικοινωνία (ανοίγει σε νέο παράθυρο)')).to be(true)
      expect(text.call(nil).utility_chrome?('Επικοινωνία (ανοίγει σε νέο παράθυρο)')).to be(false)
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::El.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:el].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Hebrew labels' do
    let(:he) { text.call(:he) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:he]) } }
    let(:readers) do
      {
        utility: ->(label) { he.utility?(label) }, chrome: ->(label) { he.utility_chrome?(label) },
        prefix: ->(label) { he.utility_prefix?(label) }, recommended: ->(label) { he.recommended?(label) },
        read_more: ->(label) { he.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels', :aggregate_failures do
      ['התחברות', 'הרשמה', 'כניסה', 'חיפוש', 'תנאי שימוש', 'מדיניות הפרטיות', 'צרו קשר', 'אודות', 'מפת האתר',
       'הצהרת נגישות', 'תגובות', 'שיתוף', 'דלג לתוכן', 'התחברות (3)', '[חיפוש]', '→ אודות →'].each do |label|
        expect(he.utility_chrome?(label)).to be(true), label
      end
      ['קראו גם', 'כתבות קשורות', 'עוד בנושא'].each { expect(he.recommended?(_1)).to be(true), _1 }
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['קראו עוד', 'להמשך קריאה', 'לכתבה המלאה', 'למידע נוסף'].each do |label|
        expect([he.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['הרשמה לניוזלטר', 'רכשו מינוי', 'הירשמו'].each { expect(he.utility_chrome?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a label word or an attached prefix a headline', :aggregate_failures do
      ['חיפוש אחר הנעדרים נמשך', 'כניסה לתוקף של החוק', 'הרשמה לבתי הספר נפתחה', 'התחברות הרשת החדשה מעכבת תושבים',
       'אודות המחקר החדש נמסר כי', 'עזרה לנפגעי השיטפון הגיעה', 'תגובות קשות לפסק הדין', 'קראו עוד מאמרים בנושא החינוך',
       'כתבות קשורות לא נמצאו בארכיון', 'שיתוף פעולה חדש בין הערים', 'סגירה של הגשר נדחתה'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year a title and reads a bracketed count as chrome', :aggregate_failures do
      ['תנאי שימוש 2026', 'מדיניות פרטיות 2026', 'כתבות קשורות 2026', 'קראו גם 2026',
       'הצהרת נגישות 2026'].each do |label|
        expect(he.utility_chrome?(label)).to be(false), label
        expect(junk_reason.call(label)).to be_nil, label
      end
      expect(he.utility_chrome?('תגובות (12)')).to be(true)
      expect(he.utility_chrome?('תגובות 12')).to be(false)
    end

    it 'reads labels wrapped in bidi marks', :aggregate_failures do
      ["\u200Fהתחברות\u200F", "\u202Bתנאי שימוש\u202C"].each { expect(he.utility_chrome?(_1)).to be(true), _1 }
      expect(junk_reason.call("\u200Fקראו עוד\u200F")).to eq(:cta)
    end

    it 'reads the labels on a Hebrew page only, and the new-window notice', :aggregate_failures do
      [nil, :ja, :en, :zh, :iw].each { expect(text.call(_1).utility_chrome?('התחברות')).to be(false), _1.inspect }
      expect(he.utility_chrome?('התחברות (נפתח בחלון חדש)')).to be(true)
      expect(text.call(nil).utility_chrome?('התחברות (נפתח בחלון חדש)')).to be(false)
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::He.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:he].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Arabic labels' do
    let(:ar) { text.call(:ar) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:ar]) } }
    let(:readers) do
      {
        utility: ->(label) { ar.utility?(label) }, chrome: ->(label) { ar.utility_chrome?(label) },
        prefix: ->(label) { ar.utility_prefix?(label) }, recommended: ->(label) { ar.recommended?(label) },
        read_more: ->(label) { ar.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or direction marks',
       :aggregate_failures do
      ['تسجيل الدخول', 'تسجيل الخروج', 'إنشاء حساب', 'بحث', 'البحث', 'من نحن', 'اتصل بنا', 'سياسة الخصوصية',
       'الشروط والأحكام',
       'خريطة الموقع', 'التعليقات', 'النشرة البريدية', 'اشتراك', 'إغلاق'].each do |item|
        expect(ar.utility_chrome?(item)).to be(true),
                                            item
      end
      ["\u200fبحث\u200f", "\u202bسياسة الخصوصية\u202c", '[إغلاق]', '← إغلاق ←',
       'تسجيل الدخول (يفتح في نافذة جديدة)'].each do |item|
        expect(ar.utility_chrome?(item)).to be(true), item
      end
      ['ذات صلة', 'مقالات ذات صلة', 'اقرأ أيضا', 'اقرأ أيضاً'].each { expect(ar.recommended?(_1)).to be(true), _1 }
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['اقرأ المزيد', 'للمزيد', 'للمزيد من التفاصيل', 'تابع القراءة', 'اقرأ المقال كاملا'].each do |label|
        expect([ar.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['اشترك الآن', 'اشترك في النشرة البريدية', 'أضف تعليقاً'].each { expect(ar.utility_chrome?(_1)).to be(true), _1 }
    end

    it 'keeps a headline that opens with a label word a headline', :aggregate_failures do
      ['بحث عن ناجين في الميناء', 'البحث عن حلول للأزمة', 'تسجيل الدخول إلى البوابة يتعطل', 'اشتراك مجاني يغير السوق',
       'المزيد من الأمطار هذا الأسبوع', 'تعليقات القراء توقف الحملة', 'شارك في الحملة آلاف', 'مشاركة المرأة ترتفع',
       'للمزيد من الأمطار', 'والمزيد', 'بالبحث', 'التسجيل مفتوح', 'من نحن اليوم', 'إغلاق المطار ليومين',
       'ذات صلة بالأزمة', 'اقرأ أيضا لماذا تغيرت الأسعار'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year a headline, and reads a label with a small count as chrome',
       :aggregate_failures do
      ['من نحن 2026', 'سياسة الخصوصية 2026', 'ذات صلة 2026', 'اقرأ أيضا 2026', 'المزيد 2026',
       'التعليقات 2026'].each do |label|
        readers.each_value do |reader|
          expect(reader.call(label)).to be(false), label
        end
      end
      ['تعليقات (12)', 'إغلاق [3]', 'بحث (7)'].each { expect(ar.utility_chrome?(_1)).to be(true), _1 }
      ['تعليقات 12', 'إغلاق 3', 'من نحن 2'].each { expect(ar.utility_chrome?(_1)).to be(false), _1 }
    end

    it 'reads the labels on a Arabic page only', :aggregate_failures do
      [nil, :ja, :en, :zh, :ko, :fa].each { expect(text.call(_1).utility_chrome?("'تسجيل")).to be(false), _1.inspect }
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::Ar.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:ar].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Persian labels' do
    let(:fa) { text.call(:fa) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:fa]) } }
    let(:readers) do
      {
        utility: ->(label) { fa.utility?(label) }, chrome: ->(label) { fa.utility_chrome?(label) },
        prefix: ->(label) { fa.utility_prefix?(label) }, recommended: ->(label) { fa.recommended?(label) },
        read_more: ->(label) { fa.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or direction marks',
       :aggregate_failures do
      ['ورود', 'خروج', 'جستجو', 'جست‌وجو', 'جست و جو', 'درباره ما', 'تماس با ما', 'حریم خصوصی',
       'نقشه سایت',
       'راهنما', 'خبرنامه', 'اشتراک', 'نظرات', 'بستن', 'صفحه اصلی'].each do |item|
        expect(fa.utility_chrome?(item)).to be(true),
                                            item
      end
      ["\u200fجستجو\u200f", "\u202bحریم خصوصی\u202c", '[بستن]', '← بستن ←',
       'ورود (در پنجره جدید باز می‌شود)'].each do |item|
        expect(fa.utility_chrome?(item)).to be(true), item
      end
      ['مطالب مرتبط', 'اخبار مرتبط', 'مطالب پیشنهادی', 'همچنین بخوانید'].each do |item|
        expect(fa.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['ادامه مطلب', 'بیشتر بخوانید', 'متن کامل', 'جزئیات بیشتر', 'ادامه مطلب را بخوانید'].each do |label|
        expect([fa.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['مشترک شوید', 'اشتراک در خبرنامه', 'نظر خود را بنویسید', 'وارد شوید'].each do |item|
        expect(fa.utility_chrome?(item)).to be(true), item
      end
    end

    it 'keeps a headline that opens with a label word a headline', :aggregate_failures do
      ['جستجو برای بازماندگان در بندر', 'ورود به پورتال مختل شد', 'اشتراک رایگان بازار را عوض کرد',
       'بیشتر از انتظار باران می‌بارد', 'نظرات خوانندگان کارزار را متوقف کرد', 'خروج بریتانیا از بازار', 'راهنمای خرید',
       'ثبت‌نام‌کنندگان بیشتر شدند', 'ورودی‌های جدید', 'بستن مرز تا فردا', 'منوی غذا گران شد', 'ادامه مطلب این نیست',
       'درباره ما چه می‌دانید', 'مطالب مرتبط با اقتصاد',
       'ورود موج جدید بارشی به کشور', 'ثبت نام و قیمت خودرو', 'قوانین و مقررات'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year a headline, and reads a label with a small count as chrome',
       :aggregate_failures do
      ['درباره ما 2026', 'حریم خصوصی 2026', 'مطالب مرتبط 2026', 'همچنین بخوانید 2026', 'بیشتر 2026',
       'نظرات 2026'].each do |label|
        readers.each_value do |reader|
          expect(reader.call(label)).to be(false), label
        end
      end
      ['نظرات (12)', 'بستن [3]', 'جستجو (7)'].each { expect(fa.utility_chrome?(_1)).to be(true), _1 }
      ['نظرات 12', 'بستن 3', 'حریم خصوصی 2', 'ثبت نام 140'].each { expect(fa.utility_chrome?(_1)).to be(false), _1 }
    end

    it 'reads the ZWNJ, spaced and Arabic-letter spellings of a label alike, and normalizes nothing',
       :aggregate_failures do
      ["ثبت\u200cنام", 'ثبت نام', 'حريم خصوصي', 'اشتراك', 'اشتراک', 'ورود به حساب كاربري', "جست\u200cوجو",
       'ورود / ثبت نام',
       "ورود و ثبت\u200cنام", 'ورود | ثبت نام', 'ورود يا ثبت نام', 'شرایط و ضوابط', 'سیاست حریم خصوصی'].each do |item|
        expect(fa.utility_chrome?(item)).to be(true), item
      end
      expect(fa.utility_chrome?("ثبت\u200cنام\u200c")).to be(true)
      expect(fa.utility_chrome?('ثبتنام')).to be(false)
      expect(fa.utility_chrome?('ورود به حساب كاربري (در پنجره جديد باز مي‌شود)')).to be(true)
    end

    it 'reads the labels on a Persian page only', :aggregate_failures do
      [nil, :ja, :en, :zh, :ko, :ar].each { expect(text.call(_1).utility_chrome?("'ورود',")).to be(false), _1.inspect }
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::Fa.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:fa].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Thai labels' do
    let(:th) { text.call(:th) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:th]) } }
    let(:readers) do
      {
        utility: ->(label) { th.utility?(label) }, chrome: ->(label) { th.utility_chrome?(label) },
        prefix: ->(label) { th.utility_prefix?(label) }, recommended: ->(label) { th.recommended?(label) },
        read_more: ->(label) { th.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      %w[เข้าสู่ระบบ ออกจากระบบ สมัครสมาชิก ค้นหา เกี่ยวกับเรา ติดต่อเรา นโยบายความเป็นส่วนตัว
         นโยบายคุกกี้ ข้อตกลงและเงื่อนไข แผนผังเว็บไซต์ แผนผังเว็บไซท์ จดหมายข่าว หน้าแรก แชร์ เมนู].each do |item|
        expect(th.utility_chrome?(item)).to be(true), item
      end
      ['[แชร์]', '← เมนู ←', 'เข้าสู่ระบบ (เปิดในหน้าต่างใหม่)', "\u200eค้นหา\u200e"].each do |item|
        expect(th.utility_chrome?(item)).to be(true), item
      end
      %w[ข่าวที่เกี่ยวข้อง บทความที่เกี่ยวข้อง ข่าวแนะนำ คุณอาจสนใจ].each do |item|
        expect(th.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      %w[อ่านต่อ อ่านเพิ่มเติม อ่านข่าวต่อ ดูรายละเอียด รายละเอียดเพิ่มเติม].each do |label|
        expect([th.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      %w[สมัครรับจดหมายข่าว แสดงความคิดเห็น สมัครสมาชิกวันนี้].each do |item|
        expect(th.utility_chrome?(item)).to be(true), item
      end
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      %w[ค้นหาผู้รอดชีวิตในท่าเรือ เข้าสู่ระบบพอร์ทัลขัดข้อง สมัครสมาชิกฟรีเปลี่ยนตลาดหนังสือพิมพ์
         ดูเพิ่มเติมได้ที่ห้องสมุดกลาง อ่านต่อไปนี้คือกำหนดการใหม่ เมนูอาหารกลางวันขึ้นราคา
         หน้าแรกของงานตลาดนัดเปิดแล้ว แชร์ข้อมูลช่วยตามหาเด็กหาย ติดต่อเราได้ทุกวันเป็นเวลาหนึ่งเดือน
         ลงทะเบียนผู้สูงอายุเพิ่มขึ้น ร่วมงานกับเราสิบตำแหน่งใหม่ ปิดท่าเรือสองวัน ข่าวที่เกี่ยวข้องกับน้ำท่วม
         ฝนตกหนักและดูเพิ่มเติม ท่าเรือเปิดค้นหาผู้สูญหาย คำถามที่พบบ่อยของผู้เช่า เพิ่มเติมจากเมื่อวาน
         ช่วยเหลือผู้ประสบภัยน้ำท่วม นโยบายคุกกี้ใหม่ของเว็บไซต์ข่าว].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['เกี่ยวกับเรา 2026', 'นโยบายความเป็นส่วนตัว 2569', 'ข่าวที่เกี่ยวข้อง 2026', 'อ่านต่อ 2026', 'ดูเพิ่มเติม 2026',
       'แชร์ 2569', 'ค้นหา 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['แชร์ (12)', 'เมนู [3]', 'ค้นหา (7)'].each { expect(th.utility_chrome?(_1)).to be(true), _1 }
      ['แชร์ 12', 'เมนู 3', 'เกี่ยวกับเรา 2', 'ค้นหา 140'].each do |label|
        expect(th.utility_chrome?(label)).to be(false), label
      end
    end

    it 'reads the labels on a Thai page only', :aggregate_failures do
      [nil, :ja, :en, :zh, :ko, :fa].each do |code|
        expect(text.call(code).utility_chrome?('เข้าสู่ระบบ')).to be(false), code.inspect
      end
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::Th.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:th].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'Turkish labels' do
    let(:tr) { text.call(:tr) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:tr]) } }
    let(:readers) do
      {
        utility: ->(label) { tr.utility?(label) }, chrome: ->(label) { tr.utility_chrome?(label) },
        prefix: ->(label) { tr.utility_prefix?(label) }, recommended: ->(label) { tr.recommended?(label) },
        read_more: ->(label) { tr.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Giriş Yap', 'Oturum Aç', 'Çıkış Yap', 'Kayıt Ol', 'Arama', 'Hakkımızda', 'İletişim', 'Bize Ulaşın',
       'Gizlilik Politikası', 'Çerez Politikası', 'Kullanım Koşulları', 'Site Haritası', 'Sıkça Sorulan Sorular',
       'Menü', 'Ana Sayfa', 'Yorumlar', 'Paylaş'].each do |item|
        expect(tr.utility_chrome?(item)).to be(true), item
      end
      ['[Paylaş]', '← Menü ←', 'Giriş Yap (yeni sekmede açılır)', "\u200eArama\u200e"].each do |item|
        expect(tr.utility_chrome?(item)).to be(true), item
      end
      ['İlgili Haberler', 'Benzer Haberler', 'İlginizi Çekebilir', 'Önerilen Yazılar'].each do |item|
        expect(tr.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Devamını Oku', 'Haberin Devamı', 'Devamı', 'Daha Fazla Oku', 'Tamamını Oku'].each do |label|
        expect([tr.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Bültene Abone Ol', 'Abone Ol', 'Yorum Yap', 'Haberi Paylaş', 'Hemen Üye Ol'].each do |item|
        expect(tr.utility_chrome?(item)).to be(true), item
      end
    end

    # The case-insensitive match folds neither Turkish pair, so the terms spell both: every i also reads the
    # dotted capital and every dotless i also reads its capital.
    it 'reads the dotted and dotless i in every case a page writes them', :aggregate_failures do
      ['giriş yap', 'GİRİŞ YAP', 'Giriş Yap', 'çıkış yap', 'ÇIKIŞ YAP', 'Çıkış Yap', 'iletişim', 'İLETİŞİM',
       'İletişim', 'hakkımızda', 'HAKKIMIZDA', 'Hakkımızda', 'gizlilik politikası', 'GİZLİLİK POLİTİKASI',
       'sıkça sorulan sorular', 'SIKÇA SORULAN SORULAR', 'kullanım koşulları', 'KULLANIM KOŞULLARI',
       'kayıt ol', 'KAYIT OL'].each do |label|
        expect(tr.utility_chrome?(label)).to be(true), label
      end
      ['İLGİLİ HABERLER', 'BENZER HABERLER', 'İLGİNİZİ ÇEKEBİLİR'].each { expect(tr.recommended?(_1)).to be(true), _1 }
      ['DEVAMINI OKU', 'HABERİN DEVAMI', 'DAHA FAZLA OKU'].each { expect(tr.read_more?(_1)).to be(true), _1 }
      ['BÜLTENE ABONE OL', 'YORUM YAP', 'HABERİ PAYLAŞ'].each { expect(tr.utility_chrome?(_1)).to be(true), _1 }
      expect(tr.utility_chrome?("i\u0307letişim")).to be(true)
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Giriş yapılamayan portal yarım gün kapalı kaldı', 'Abone ol çağrısı gazete pazarını değiştirdi',
       'Daha fazla bisiklet yolu için imza toplandı', 'İletişim ağı belediye binasında yenilendi',
       'Hakkımızda kısa film festivali bugün başladı', 'Çıkış yapan sürücüler yeni şeridi kullanacak',
       'Yorumlar kapatıldı, tartışma sürüyor', 'Menü fiyatları ikiye katlandı',
       'Arama kurtarma ekibi gece boyunca çalıştı',
       'Paylaş düğmesi kaldırıldı', 'İlgili haberler arasında yeni bir ayrıntı çıktı',
       'GİRİŞ YAPILAMAYAN PORTAL YARIM GÜN KAPALI', 'Devamı gelmeyen yol yapımı sürüyor'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Hakkımızda 2026', 'İletişim 2026', 'İlgili Haberler 2026', 'Devamını Oku 2026', 'Giriş Yap 2026',
       'Gizlilik Politikası 2026', 'Menü 2026', 'ÇIKIŞ YAP 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Menü (12)', 'Paylaş [3]', 'Arama (7)', 'Yorumlar (12)'].each do |item|
        expect(tr.utility_chrome?(item)).to be(true), item
      end
      ['Menü 12', 'Paylaş 3', 'Hakkımızda 2', 'Yorumlar 140'].each do |label|
        expect(tr.utility_chrome?(label)).to be(false), label
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      %w[Gündem Spor Ekonomi Dünya Giriş Çıkış Bülten Yardım Abonelik Ara Önceki Sonraki Detaylar
         Reklam].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'keeps every foreign ambiguous term reading as chrome on a Turkish page, and a longer headline a headline',
       :aggregate_failures do
      %w[Dela Teilen Plus Comment].each do |label|
        expect(tr.utility_chrome?(label)).to be(true), label
        expect(text.call(nil).utility_chrome?(label)).to be(true), label
      end
      ['Plus Çarşısı yeniden kapılarını açtı', 'Dela Vadisi turizm sezonunu uzattı',
       'Über Köprüsü trafiğe kapatıldı'].each do |headline|
        expect(tr.utility_chrome?(headline)).to be(false), headline
        expect(tr.recommended?(headline)).to be(false), headline
        expect(tr.read_more?(headline)).to be(false), headline
      end
    end

    it 'reads a dotless i label with a dotted i, but not a label missing its other Turkish letters',
       :aggregate_failures do
      ['Hakkimizda', 'KAYIT OL', 'kayit ol', 'HAKKIMIZDA'].each { expect(tr.utility_chrome?(_1)).to be(true), _1 }
      ['Iletisim', 'CIKIS YAP'].each { expect(tr.utility_chrome?(_1)).to be(false), _1 }
    end

    it 'reads the labels on a Turkish page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :ko].each do |code|
        expect(text.call(code).utility_chrome?('Giriş Yap')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Tr.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:tr].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Tr.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Hungarian labels' do
    let(:hu) { text.call(:hu) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:hu]) } }
    let(:readers) do
      {
        utility: ->(label) { hu.utility?(label) }, chrome: ->(label) { hu.utility_chrome?(label) },
        prefix: ->(label) { hu.utility_prefix?(label) }, recommended: ->(label) { hu.recommended?(label) },
        read_more: ->(label) { hu.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Belépés', 'Bejelentkezés', 'Kijelentkezés', 'Regisztráció', 'Keresés', 'Rólunk', 'Impresszum', 'Kapcsolat',
       'Médiaajánlat', 'Adatvédelmi tájékoztató', 'Felhasználási feltételek', 'Süti beállítások', 'ÁSZF',
       'Moderálási szabályzat', 'Hírlevél', 'Menü', 'Címlap', 'Ugrás a tartalomhoz', 'Hozzászólások',
       'Megosztás'].each do |item|
        expect(hu.utility_chrome?(item)).to be(true), item
      end
      ['[Hírlevél]', '← Menü ←', 'Belépés (új ablakban nyílik meg)', "\u200eKeresés\u200e"].each do |item|
        expect(hu.utility_chrome?(item)).to be(true), item
      end
      ['Kapcsolódó cikkek', 'Ajánlott hírek', 'Ez is érdekelhet', 'Olvasd el ezt is'].each do |item|
        expect(hu.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Tovább', 'Bővebben', 'Olvass tovább', 'Teljes cikk', 'Tudj meg többet'].each do |label|
        expect([hu.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Iratkozzon fel hírlevelünkre', 'Feliratkozom a hírlevélre', 'Hozzászólás írása',
       'Oszd meg a cikket'].each do |item|
        expect(hu.utility_chrome?(item)).to be(true), item
      end
    end

    it 'reads the labels in upper case, with the double-acute letters and in decomposed form', :aggregate_failures do
      ['BEJELENTKEZÉS', 'KIJELENTKEZÉS', 'BELÉPÉS', 'KERESÉS', 'RÓLUNK', 'ADATVÉDELMI TÁJÉKOZTATÓ', 'MENÜ',
       'HOZZÁSZÓLÁSOK', 'HÍRLEVÉL'].each do |label|
        expect(hu.utility_chrome?(label)).to be(true), label
      end
      ['KAPCSOLÓDÓ CIKKEK', 'EZ IS ÉRDEKELHET', 'ÖNNEK AJÁNLJUK', 'OLVASD EL EZT IS'].each do |label|
        expect(hu.recommended?(label)).to be(true), label
      end
      ['TOVÁBB', 'BŐVEBBEN', 'OLVASS TOVÁBB', 'TELJES CIKK'].each { expect(hu.read_more?(_1)).to be(true), _1 }
      ['Bejelentkezés', 'Önnek ajánljuk', 'Ez is érdekelhet', 'Kövessen minket', 'Bővebben'].each do |label|
        decomposed = label.unicode_normalize(:nfd)
        expect(decomposed).not_to eq(label)
        reads = [hu.utility_chrome?(decomposed), hu.recommended?(decomposed), hu.read_more?(decomposed)]
        expect(reads).to include(true), label
      end
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Belépés nélkül is látogatható lesz a kiállítás szombaton', 'Keresés közben megtalálták az eltűnt turistát',
       'Kapcsolat a két part között: új gyalogoshíd épül', 'Tovább nő a vízállás a Tiszán',
       'Összes fiókját törölte az önkormányzat a közösségi oldalon', 'Hírlevél helyett papírújság a postaládákban',
       'Rólunk szól a nyári fesztivál nyitóelőadása', 'Regisztráció nélkül szavazhatnak a helyiek',
       'Menü az iskolai étkezdében: kevesebb cukor, több zöldség', 'Megosztás helyett közös játék a tavaszi napon',
       'Bővebben a helyi piac új nyitvatartásáról', 'Impresszum nélkül jelent meg az évkönyv',
       'BELÉPÉS NÉLKÜL IS LÁTOGATHATÓ LESZ A KIÁLLÍTÁS', 'Kapcsolódó cikkek helyett ajánló: az új kerékpárút',
       'Ez is érdekelhet minket: a városi könyvtár nyitva marad'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Kapcsolat 2026', 'Keresés 2026', 'Kapcsolódó cikkek 2026', 'Tovább 2026', 'Belépés 2026', 'Impresszum 2026',
       'Hírlevél 2026', 'BEJELENTKEZÉS 2026', 'Tovább 3', 'Keresés 12'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Hírlevél (12)', 'Menü [3]', 'Keresés (7)', 'Hozzászólások (12)'].each do |item|
        expect(hu.utility_chrome?(item)).to be(true), item
      end
      ['Hírlevél 12', 'Menü 3', 'Kapcsolat 2', 'Hozzászólások 140'].each do |label|
        expect(hu.utility_chrome?(label)).to be(false), label
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      ['Belföld', 'Külföld', 'Sport', 'Gazdaság', 'Vélemény', 'Videó', 'Friss hírek', 'Hirdetés', 'Támogatás',
       'Profil', 'Folytatás', 'Részletek', 'Karrier', 'Előfizetés', 'Népszerű', 'Legfrissebb'].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'leaves the bare more labels out, so a card linked by one stays a card', :aggregate_failures do
      ['Még több', 'Mutass többet', 'Továbbiak', 'MÉG TÖBB'].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'reads a list-level label as read-more, never chrome, so a card keeps its item', :aggregate_failures do
      ['Még több hír', 'Még több cikk', 'További hírek', 'További cikkek', 'Összes', 'Összes hír',
       'Tovább a rovatra'].each do |label|
        expect([hu.utility_chrome?(label), hu.read_more?(label)]).to eq([false, true]), label
      end
    end

    it 'reads a bracketed count after an own read-more label as read-more, never chrome', :aggregate_failures do
      ['Tovább (3)', 'Tovább [3]', 'Bővebben (3)', 'További hírek [3]', 'Összes （3）'].each do |label|
        expect([hu.read_more?(label), hu.utility_chrome?(label)]).to eq([true, false]), label
      end
      ['Tovább 3', 'További hírek 2026', 'Tovább (1234)'].each { expect(hu.read_more?(_1)).to be(false), _1 }
    end

    it 'keeps a headline of three Hungarian words above the title floor', :aggregate_failures do
      ['Éjjeli piac nyit újra', 'Kompmenet változik hétfőtől', 'Aranyár nőtt tovább'].each do |headline|
        expect(junk_reason.call(headline)).to be_nil, headline
      end
    end

    it 'reads the labels on a Hungarian page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :tr].each do |code|
        expect(text.call(code).utility_chrome?('Bejelentkezés')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Hu.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:hu].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Hu.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Vietnamese labels' do
    let(:vi) { text.call(:vi) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:vi]) } }
    let(:readers) do
      {
        utility: ->(label) { vi.utility?(label) }, chrome: ->(label) { vi.utility_chrome?(label) },
        prefix: ->(label) { vi.utility_prefix?(label) }, recommended: ->(label) { vi.recommended?(label) },
        read_more: ->(label) { vi.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Đăng nhập', 'Đăng xuất', 'Đăng ký', 'Đăng kí', 'ĐĂNG KÍ',
       'Tạo tài khoản', 'Tìm kiếm', 'Về chúng tôi', 'Liên hệ',
       'Liên hệ tòa soạn', 'Chính sách bảo mật', 'Điều khoản sử dụng', 'Trang chủ', 'Menu', 'Bình luận',
       'Chia sẻ', 'Tải ứng dụng', 'Chuyển đến nội dung chính'].each do |item|
        expect(vi.utility_chrome?(item)).to be(true), item
      end
      ['[Menu]', '← Trang chủ ←', 'Đăng nhập (mở trong tab mới)', "\u200eTìm kiếm\u200e"].each do |item|
        expect(vi.utility_chrome?(item)).to be(true), item
      end
      ['Tin liên quan', 'Bài viết liên quan', 'Có thể bạn quan tâm', 'Gợi ý cho bạn'].each do |item|
        expect(vi.recommended?(item)).to be(true), item
      end
    end

    it 'reads a bracketed count after an own read-more label as read-more, a bare number or a year as a title',
       :aggregate_failures do
      ['Xem tất cả [3]', 'Xem thêm (12)', 'Xem tất cả ［3］'].each do |label|
        expect([vi.read_more?(label), vi.utility_chrome?(label)]).to eq([true, false]), label
      end
      ['Xem tất cả 3', 'Xem tất cả 2026', 'Xem tất cả (1234)'].each { expect(vi.read_more?(_1)).to be(false), _1 }
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Đọc tiếp', 'Đọc thêm', 'Xem chi tiết', 'Đọc toàn bộ bài viết'].each do |label|
        expect([vi.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Đăng ký nhận bản tin', 'Đăng ký ngay', 'Gửi bình luận', 'Chia sẻ bài viết'].each do |item|
        expect(vi.utility_chrome?(item)).to be(true), item
      end
    end

    it 'reads the labels in upper case and in decomposed form', :aggregate_failures do
      ['ĐĂNG NHẬP', 'ĐĂNG XUẤT', 'TÌM KIẾM', 'LIÊN HỆ', 'CHÍNH SÁCH BẢO MẬT', 'TRANG CHỦ'].each do |label|
        expect(vi.utility_chrome?(label)).to be(true), label
      end
      ['TIN LIÊN QUAN', 'BÀI VIẾT LIÊN QUAN'].each { expect(vi.recommended?(_1)).to be(true), _1 }
      ['ĐỌC TIẾP', 'XEM CHI TIẾT'].each { expect(vi.read_more?(_1)).to be(true), _1 }
      ['Đăng nhập', 'Tìm kiếm', 'Chính sách bảo mật', 'Tin liên quan'].each do |label|
        decomposed = label.unicode_normalize(:nfd)
        expect(decomposed).not_to eq(label)
        expect(vi.utility_chrome?(decomposed) || vi.recommended?(decomposed)).to be(true), label
      end
      expect(vi.read_more?('Đọc tiếp'.unicode_normalize(:nfd))).to be(true)
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Đăng nhập cổng dịch vụ công lỗi suốt nửa ngày', 'Tìm kiếm cứu nạn kéo dài suốt đêm',
       'Liên hệ viên chức thị trấn nhận bằng khen', 'Chia sẻ sách cũ giúp quỹ học bổng',
       'Xem thêm lớp vẽ miễn phí mở vào cuối tuần', 'Bình luận viên trẻ giành giải xuất sắc',
       'Đăng ký cư trú trực tuyến mở lại', 'Đăng kí cư trú trực tuyến mở lại',
       'Về chúng tôi liên hoan phim ngắn khai mạc',
       'Trang chủ nhà văn được đặt tên đường', 'Đọc tiếp lời kể của người sống sót',
       'Tin liên quan vụ cháy được công bố', 'ĐĂNG NHẬP CỔNG DỊCH VỤ CÔNG LỖI NỬA NGÀY'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Liên hệ 2026', 'Tìm kiếm 2026', 'Tin liên quan 2026', 'Đọc tiếp 2026', 'Đăng nhập 2026',
       'Chính sách bảo mật 2026', 'Xem thêm 2026', 'ĐĂNG KÝ 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Trang chủ (12)', 'Menu [3]', 'Tìm kiếm (7)', 'Bình luận (12)'].each do |item|
        expect(vi.utility_chrome?(item)).to be(true), item
      end
      ['Trang chủ 12', 'Menu 3', 'Liên hệ 2', 'Bình luận 140'].each do |label|
        expect(vi.utility_chrome?(label)).to be(false), label
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      ['Thế giới', 'Thể thao', 'Kinh doanh', 'Thời sự', 'Quảng cáo', 'Giới thiệu', 'Chi tiết', 'Hủy bỏ', 'Tin khác',
       'Mới nhất', 'Xem nhiều', '2 liên quan'].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'keeps a headline of three Vietnamese words above the title floor', :aggregate_failures do
      ['Chợ đêm mở lại', 'Bến phà đổi giờ chạy', 'Giá vàng tăng mạnh'].each do |headline|
        expect(junk_reason.call(headline)).to be_nil, headline
      end
    end

    it 'reads the labels on a Vietnamese page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :tr].each do |code|
        expect(text.call(code).utility_chrome?('Đăng nhập')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Vi.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:vi].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Vi.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Danish labels' do
    let(:da) { text.call(:da) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:da]) } }
    let(:readers) do
      {
        utility: ->(label) { da.utility?(label) }, chrome: ->(label) { da.utility_chrome?(label) },
        prefix: ->(label) { da.utility_prefix?(label) }, recommended: ->(label) { da.recommended?(label) },
        read_more: ->(label) { da.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Log ind', 'Log på', 'Log ud', 'Opret bruger', 'Opret konto', 'Søg', 'Søgning', 'Om os', 'Tip os',
       'Kundeservice', 'Privatlivspolitik', 'Persondatapolitik', 'Cookiepolitik', 'Cookieindstillinger',
       'Vilkår og betingelser', 'Ofte stillede spørgsmål', 'Menu', 'Åbn menu', 'Forside', 'Kommentarer',
       'Følg os', 'Spring til indhold',
       'Gå til hovedindhold'].each do |item|
        expect(da.utility_chrome?(item)).to be(true), item
      end
      ['[Søg]', '← Søg ←', 'Log ind (åbner i nyt vindue)', '‎Søg‎'].each do |item|
        expect(da.utility_chrome?(item)).to be(true), item
      end
      ['Relaterede artikler', 'Relaterede historier', 'Læs også', 'Se også', 'Anbefalet til dig'].each do |item|
        expect(da.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Læs mere', 'Læs mere her', 'Læs hele artiklen', 'Læs videre', 'Læs resten', 'Se mere',
       'Vis mere'].each do |label|
        expect([da.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Tilmeld dig nyhedsbrev', 'Køb abonnement', 'Bliv abonnent', 'Skriv en kommentar', 'Del artiklen'].each do |item|
        expect(da.utility_chrome?(item)).to be(true), item
      end
    end

    it 'reads the labels in upper case and in decomposed form', :aggregate_failures do
      ['LOG IND', 'SØG', 'OM OS', 'PRIVATLIVSPOLITIK', 'VILKÅR OG BETINGELSER', 'TIP OS',
       'GÅ TIL INDHOLD'].each do |label|
        expect(da.utility_chrome?(label)).to be(true), label
      end
      ['RELATEREDE ARTIKLER', 'LÆS OGSÅ'].each { expect(da.recommended?(_1)).to be(true), _1 }
      ['LÆS MERE', 'LÆS HELE ARTIKLEN'].each { expect(da.read_more?(_1)).to be(true), _1 }
      ['Log ind', 'Søg', 'Om os', 'Privatlivspolitik', 'Vilkår og betingelser', 'Læs også'].each do |label|
        decomposed = label.unicode_normalize(:nfd)
        expect(da.utility_chrome?(decomposed) || da.recommended?(decomposed)).to be(true), label
      end
      expect('Vilkår og betingelser'.unicode_normalize(:nfd)).not_to eq('Vilkår og betingelser')
      expect(da.read_more?('Læs mere'.unicode_normalize(:nfd))).to be(true)
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Log ind ramte portalen, som lå nede en halv dag', 'Søg efter savnet fisker er indstillet',
       'Læs mere end ventet: lånerne slår rekord', 'Om os og kortfilmfestivalen, som begynder i dag',
       'Se også naboens have, som vandt prisen for årets bed', 'Del af byens gamle havn bliver til park',
       'Cookiepolitik i bageriet: kunderne får gratis småkager', 'LOG IND RAMTE PORTALEN HELE DAGEN'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Log ind 2026', 'Søg 2026', 'Læs mere 2026', 'Om os 2026', 'Privatlivspolitik 2026',
       'Relaterede artikler 2026', 'Tip os 2026', 'Vilkår og betingelser 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Tip os 12', 'Søg 3', 'Log ind 2', 'Om os 3'].each do |label|
        expect(da.utility_chrome?(label)).to be(false), label
      end
      ['Tip os (12)', 'Søg [3]', 'Søg (7)', 'Kommentarer (12)'].each do |item|
        expect(da.utility_chrome?(item)).to be(true), item
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      ['Del', 'Hjælp', 'Annoncering', 'Lyt', 'Seneste nyt', 'Mest læste', 'Udland', 'Kultur', 'Debat',
       'Erhverv', 'Del 2'].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'reads Kontakt and Kommentarer through the foreign readings every scope shares',
       :aggregate_failures do
      ['Kontakt', 'Kontakt Danmark', 'Kontakt 2026', 'Kommentarer 140'].each do |label|
        expect([da.utility_chrome?(label), text.call(:all).utility_chrome?(label)]).to eq([true, true]), label
      end
      expect(da.utility_chrome?('Kontakt mellem skakspillerne forbudt')).to be(false)
    end

    it 'reads a list-level label as read-more, never chrome, so a card keeps its item', :aggregate_failures do
      ['Se alle', 'Se flere', 'Flere nyheder'].each do |label|
        expect([da.utility_chrome?(label), da.read_more?(label)]).to eq([false, true]), label
      end
      expect([da.read_more?('Vis mere'), junk_reason.call('Vis mere')]).to eq([true, :cta])
    end

    it 'reads the labels on a Danish page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :id].each do |code|
        expect(text.call(code).utility_chrome?('Log ind')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Da.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:da].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Da.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Finnish labels' do
    let(:fi) { text.call(:fi) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:fi]) } }
    let(:readers) do
      {
        utility: ->(label) { fi.utility?(label) }, chrome: ->(label) { fi.utility_chrome?(label) },
        prefix: ->(label) { fi.utility_prefix?(label) }, recommended: ->(label) { fi.recommended?(label) },
        read_more: ->(label) { fi.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Kirjaudu sisään', 'Kirjaudu ulos', 'Rekisteröidy', 'Luo tunnus', 'Hae', 'Haku', 'Ota yhteyttä',
       'Yhteystiedot', 'Asiakaspalvelu', 'Tietoa meistä', 'Tietosuoja', 'Tietosuojaseloste', 'Tietosuojalauseke',
       'Tietosuojakuvaus', 'Evästekäytännöt', 'Evästeasetukset', 'Käyttöehdot', 'Käyttö- ja sopimusehdot',
       'Usein kysytyt kysymykset', 'Valikko', 'Sulje valikko', 'Etusivu', 'Kommentit', 'Seuraa meitä',
       'Siirry pääsisältöön', 'Hyppää sisältöön', 'Saavutettavuusseloste'].each do |item|
        expect(fi.utility_chrome?(item)).to be(true), item
      end
      ['[Haku]', '← Haku ←', 'Kirjaudu sisään (avautuu uuteen ikkunaan)', '‎Haku‎'].each do |item|
        expect(fi.utility_chrome?(item)).to be(true), item
      end
      ['Lue myös', 'Katso myös', 'Samasta aiheesta', 'Aiheeseen liittyvät jutut', 'Muut lukivat myös'].each do |item|
        expect(fi.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Lue lisää', 'Lue lisää tästä', 'Lue koko juttu', 'Lue koko artikkeli', 'Lue koko uutinen',
       'Lue loppuun', 'Jatka lukemista'].each do |label|
        expect([fi.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Tilaa uutiskirje', 'Tilaa lehti', 'Ryhdy tilaajaksi', 'Kirjoita kommentti', 'Jaa artikkeli'].each do |item|
        expect(fi.utility_chrome?(item)).to be(true), item
      end
    end

    it 'reads the labels in upper case and in decomposed form', :aggregate_failures do
      ['KIRJAUDU SISÄÄN', 'HAKU', 'TIETOA MEISTÄ', 'TIETOSUOJASELOSTE', 'KÄYTTÖEHDOT', 'OTA YHTEYTTÄ',
       'SIIRRY SISÄLTÖÖN'].each do |label|
        expect(fi.utility_chrome?(label)).to be(true), label
      end
      ['LUE MYÖS', 'AIHEESTA LISÄÄ'].each { expect(fi.recommended?(_1)).to be(true), _1 }
      ['LUE LISÄÄ', 'LUE KOKO ARTIKKELI'].each { expect(fi.read_more?(_1)).to be(true), _1 }
      ['Kirjaudu sisään', 'Tietoa meistä', 'Käyttöehdot', 'Evästekäytännöt', 'Lue myös'].each do |label|
        decomposed = label.unicode_normalize(:nfd)
        expect(fi.utility_chrome?(decomposed) || fi.recommended?(decomposed)).to be(true), label
      end
      expect('Käyttöehdot'.unicode_normalize(:nfd)).not_to eq('Käyttöehdot')
      expect(fi.read_more?('Lue lisää'.unicode_normalize(:nfd))).to be(true)
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Kirjaudu sisään -ongelma lamautti kaupungin palvelut puoleksi päiväksi',
       'Hae apua ei tarvinnut: kirjasto avautui aamulla jo seitsemältä',
       'Lue lisää kiinnostaa kaikkia kirjastossa, kertoo lainaustilasto',
       'Haku kadonneen kalastajan jälkeen keskeytettiin huonon sään takia',
       'Ota yhteyttä rannan asukkaisiin, pyytää kaupunki naapurustolta',
       'Tietoa meistä kertoo uusi näyttely, joka avautuu satamassa tänään',
       'Valikko uusiutuu: koulun ruokala tarjoaa nyt kasvisvaihtoehdon',
       'Lue myös naapurin puutarha, joka voitti vuoden kukkapenkin palkinnon',
       'KIRJAUDU SISÄÄN -ONGELMA LAMAUTTI KAUPUNGIN PALVELUT'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Kirjaudu sisään 2026', 'Haku 2026', 'Lue lisää 2026', 'Tietoa meistä 2026', 'Tietosuojaseloste 2026',
       'Lue myös 2026', 'Ota yhteyttä 2026', 'Käyttöehdot 2026', 'Käyttö- ja sopimusehdot 2026',
       'Katso myös 2026', 'Usein kysytyt kysymykset 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Ota yhteyttä 12', 'Haku 3', 'Kirjaudu sisään 2', 'Tietoa meistä 3', 'Lue lisää 112'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Ota yhteyttä (12)', 'Haku [3]', 'Haku (7)', 'Kommentit (12)'].each do |item|
        expect(fi.utility_chrome?(item)).to be(true), item
      end
      ['Lue lisää (3)', 'Lue lisää [3]'].each { expect(fi.read_more?(_1)).to be(true), _1 }
    end

    it 'leaves out every section, pager, imperative and plausible-headline label', :aggregate_failures do
      ['Tilaa', 'Jaa', 'Kommentoi', 'Etsi', 'Kuuntele', 'Pelaa', 'Luetuimmat', 'Uusimmat', 'Kotimaa', 'Ulkomaat',
       'Urheilu', 'Talous', 'Kulttuuri', 'Mainos', 'Osa 2'].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'reads a list-level label as read-more, never chrome, so a card keeps its item', :aggregate_failures do
      ['Näytä kaikki', 'Katso kaikki', 'Näytä lisää', 'Lisää uutisia', 'Kaikki uutiset', 'Kaikki artikkelit',
       'Näytä kaikki (3)', 'Katso kaikki [3]'].each do |label|
        expect([fi.utility_chrome?(label), fi.utility?(label), fi.read_more?(label)]).to eq([false, false, true]), label
      end
      expect(described_class::Fi.terms.fetch(:utility) + described_class::Fi.terms.fetch(:utility_cta))
        .not_to include(*described_class::Fi.terms.fetch(:list_more))
    end

    it 'reads the labels on a Finnish page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :id].each do |code|
        expect(text.call(code).utility_chrome?('Kirjaudu sisään')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Fi.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:fi].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Fi.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Indonesian labels' do
    let(:id) { text.call(:id) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:id]) } }
    let(:readers) do
      {
        utility: ->(label) { id.utility?(label) }, chrome: ->(label) { id.utility_chrome?(label) },
        prefix: ->(label) { id.utility_prefix?(label) }, recommended: ->(label) { id.recommended?(label) },
        read_more: ->(label) { id.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Masuk', 'Daftar', 'Cari', 'Pencarian', 'Tentang Kami', 'Hubungi Kami', 'Kontak', 'Pedoman Media Siber',
       'Info Iklan', 'Kebijakan Privasi', 'Syarat dan Ketentuan', 'Peta Situs', 'Pusat Bantuan', 'Menu',
       'Tutup Menu', 'Beranda', 'Komentar', 'Bagikan',
       'Ikuti Kami', 'TENTANG KAMI'].each do |item|
        expect(id.utility_chrome?(item)).to be(true), item
      end
      ['[Beranda]', '← Beranda ←', 'Masuk (buka di tab baru)', "\u200eCari\u200e"].each do |item|
        expect(id.utility_chrome?(item)).to be(true), item
      end
      ['Berita Terkait', 'Artikel Terkait', 'Baca Juga', 'Rekomendasi untuk Anda', 'Anda Mungkin Suka'].each do |item|
        expect(id.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Baca Selengkapnya', 'BACA SELENGKAPNYA', 'Selengkapnya', 'Lihat Selengkapnya', 'Tonton Selengkapnya',
       'Lanjutkan Membaca'].each do |label|
        expect([id.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Berlangganan Newsletter', 'Daftar Sekarang', 'Tulis Komentar', 'Bagikan Artikel Ini'].each do |item|
        expect(id.utility_chrome?(item)).to be(true), item
      end
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Masuk bursa, saham pelabuhan naik tajam', 'Daftar harga tiket kapal feri naik bulan depan',
       'Cari tahu jadwal kapal malam di dermaga', 'Pencarian nelayan hilang dihentikan sementara',
       'Tentang kami dan pasar malam di alun-alun', 'Kontak fisik dilarang dalam turnamen catur',
       'Menu berbuka murah dijual di pasar tengah', 'Lainnya masih menunggu giliran di loket',
       'Komentar warga soal jalan baru membanjiri kantor', 'Bagikan sembako dilakukan serentak di kecamatan',
       'Beranda tua di tepi pelabuhan dipugar', 'Baca juga buku anak di perpustakaan keliling',
       'Berlangganan koran digital naik dua kali lipat', 'Selengkapnya soal tarif bus ada di rapat dewan',
       'MASUK BURSA, SAHAM PELABUHAN NAIK TAJAM'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Tentang Kami 2026', 'Hubungi Kami 2026', 'Berita Terkait 2026', 'Baca Selengkapnya 2026', 'Masuk Akun 2026',
       'Kebijakan Privasi 2026', 'Lihat Semua 2026', 'Cari 2026', 'Pusat Bantuan 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Beranda (12)', 'Menu [3]', 'Pencarian (7)', 'Komentar (12)'].each do |item|
        expect(id.utility_chrome?(item)).to be(true), item
      end
      ['Beranda 12', 'Menu 3', 'Tentang Kami 2', 'Komentar 140'].each do |label|
        expect(id.utility_chrome?(label)).to be(false), label
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      %w[Nasional Bola Ekonomi Otomotif Bantuan Iklan Redaksi Karir Berlangganan Indeks Sebelumnya Berikutnya
         Terpopuler].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'keeps every foreign ambiguous term reading as chrome on an Indonesian page, and a longer headline a headline',
       :aggregate_failures do
      %w[Dela Teilen Plus Comment].each do |label|
        expect(id.utility_chrome?(label)).to be(true), label
        expect(text.call(nil).utility_chrome?(label)).to be(true), label
      end
      ['Plus Pasar Baru dibuka lagi di tengah kota', 'Dela Lembah wisata diperpanjang musimnya'].each do |headline|
        expect(id.utility_chrome?(headline)).to be(false), headline
        expect(id.recommended?(headline)).to be(false), headline
        expect(id.read_more?(headline)).to be(false), headline
      end
    end

    it 'reads the labels on an Indonesian page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :tr].each do |code|
        expect(text.call(code).utility_chrome?('Tentang Kami')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Id.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:id].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Id.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Czech labels' do
    let(:cs) { text.call(:cs) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:cs]) } }
    let(:readers) do
      {
        utility: ->(label) { cs.utility?(label) }, chrome: ->(label) { cs.utility_chrome?(label) },
        prefix: ->(label) { cs.utility_prefix?(label) }, recommended: ->(label) { cs.recommended?(label) },
        read_more: ->(label) { cs.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Přihlásit se', 'Přihlaste se', 'Odhlásit se', 'Registrovat se', 'Hledat', 'O nás', 'Kontakt', 'Kontakty',
       'Ochrana osobních údajů', 'Zásady ochrany soukromí', 'Nastavení cookies', 'Obchodní podmínky',
       'Mapa stránek', 'Nápověda', 'Časté dotazy', 'Menu', 'Úvodní stránka',
       'Přeskočit na obsah', 'Můj účet', 'Sdílet'].each do |item|
        expect(cs.utility_chrome?(item)).to be(true), item
      end
      ['[Menu]', '← Sdílet ←', 'Přihlásit se (otevře se v novém okně)',
       "\u200eHledat\u200e"].each do |item|
        expect(cs.utility_chrome?(item)).to be(true), item
      end
      ['Související články', 'Podobné články', 'Mohlo by vás zajímat', 'Čtěte také', 'Doporučujeme'].each do |item|
        expect(cs.recommended?(item)).to be(true), item
      end
    end

    it 'reads a bracketed count after an own read-more label as read-more, a bare number or a year as a title',
       :aggregate_failures do
      ['Další články (12)', 'Zobrazit všechny [3]', 'Další články （12）'].each do |label|
        expect([cs.read_more?(label), cs.utility_chrome?(label)]).to eq([true, false]), label
      end
      ['Další články 3', 'Další články 2026', 'Další články (1234)'].each { expect(cs.read_more?(_1)).to be(false), _1 }
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Číst dále', 'Číst více', 'Celý článek', 'Pokračovat ve čtení', 'Přečtěte si více'].each do |label|
        expect([cs.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Odebírat newsletter', 'Přihlásit se k odběru', 'Přidat komentář', 'Sdílet článek',
       'Zaregistrovat se'].each do |item|
        expect(cs.utility_chrome?(item)).to be(true), item
      end
    end

    it 'reads a label in upper case with diacritics and in NFC or NFD', :aggregate_failures do
      ['PŘIHLÁSIT SE', 'ODHLÁSIT SE', 'O NÁS', 'OCHRANA OSOBNÍCH ÚDAJŮ', 'ČASTÉ DOTAZY', 'ÚVODNÍ STRÁNKA',
       'Přihlásit se'.unicode_normalize(:nfd)].each do |label|
        expect(cs.utility_chrome?(label)).to be(true), label
      end
      ['SOUVISEJÍCÍ ČLÁNKY', 'ČTĚTE TAKÉ'].each { expect(cs.recommended?(_1)).to be(true), _1 }
      expect(cs.read_more?('ČÍST DÁLE')).to be(true)
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Přihlásit se nemohly stovky lidí, portál byl půl dne mimo provoz',
       'Odebírat newsletter začalo dvakrát víc čtenářů než loni', 'Kontakty ministrů s lobbisty zveřejní úřad',
       'O nás bez nás: obec rozhodovala o náměstí', 'Menu ve školních jídelnách zdraží od ledna',
       'Další články o opravě mostu vyjdou v prosinci', 'Sdílet auta ve městě by chtěla polovina obyvatel',
       'Hledat pohřešovanou ženu pomáhají stovky lidí', 'Doporučujeme zůstat doma, řekl hejtman',
       'Číst dále nebudou muset ani žáci prvních tříd', 'Čtěte také? Radnice chce zavřít knihovnu',
       'PŘIHLÁSIT SE NEMOHLY STOVKY LIDÍ, PORTÁL BYL MIMO PROVOZ'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['O nás 2026', 'Kontakty 2026', 'Přihlásit se 2026', 'Související články 2026', 'Číst dále 2026',
       'Ochrana soukromí 2026', 'Zobrazit všechny 2026', 'ODHLÁSIT SE 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Menu (12)', 'Sdílet [3]', 'Hledat (7)', 'Kontakty (12)'].each do |item|
        expect(cs.utility_chrome?(item)).to be(true), item
      end
      ['Menu 12', 'Sdílet 3', 'O nás 2', 'Kontakty 140'].each do |label|
        expect(cs.utility_chrome?(label)).to be(false), label
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      %w[Sport Ekonomika Kultura Svět Komentář Komentáře Redakce Registrace Přihlášení Předplatné Inzerce Reklama
         Zavřít Více Vše Cookies Předchozí Další Detail].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    it 'keeps every foreign ambiguous term reading as chrome on a Czech page, and a longer headline a headline',
       :aggregate_failures do
      %w[Dela Teilen Plus Comment].each do |label|
        expect(cs.utility_chrome?(label)).to be(true), label
        expect(text.call(nil).utility_chrome?(label)).to be(true), label
      end
      ['Plus Pasáž znovu otevřela dveře', 'Dela Údolí prodloužilo turistickou sezonu'].each do |headline|
        expect(cs.utility_chrome?(headline)).to be(false), headline
        expect(cs.recommended?(headline)).to be(false), headline
        expect(cs.read_more?(headline)).to be(false), headline
      end
    end

    it 'reads the labels on a Czech page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :tr].each do |code|
        expect(text.call(code).utility_chrome?('Přihlásit se')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Cs.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:cs].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Cs.terms.fetch(_1) }).to be_empty
    end
  end

  describe 'Hindi labels' do
    let(:hi) { text.call(:hi) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:hi]) } }
    let(:readers) do
      {
        utility: ->(label) { hi.utility?(label) }, chrome: ->(label) { hi.utility_chrome?(label) },
        prefix: ->(label) { hi.utility_prefix?(label) }, recommended: ->(label) { hi.recommended?(label) },
        read_more: ->(label) { hi.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels', :aggregate_failures do
      ['लॉग इन', 'लॉगिन', 'साइन इन', 'सर्च', 'मेन्यू', 'संपर्क करें', 'हमारे बारे में',
       'प्राइवेसी पॉलिसी', 'गोपनीयता नीति', 'इस्तेमाल की शर्तें', 'सदस्यता', 'सहायता',
       'न्यूज़लेटर', 'लॉगिन (3)', '[सर्च]', '→ सर्च →'].each do |label|
        expect(hi.utility_chrome?(label)).to be(true), label
      end
      ['संबंधित खबरें', 'यह भी पढ़ें', 'संबंधित लेख', 'संबंधित खबरें (3)'].each do |label|
        expect(hi.recommended?(label)).to be(true), label
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['और पढ़ें', 'और देखें', 'पूरी खबर पढ़ें', 'विस्तार से पढ़ें', 'अधिक जानें'].each do |label|
        expect([hi.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['सब्सक्राइब करें', 'सदस्यता लें', 'अभी सब्सक्राइब करें', 'शेयर करें', 'साइन इन करें'].each do |label|
        expect(hi.utility_chrome?(label)).to be(true), label
      end
    end

    it 'keeps a headline that opens with a label word a headline', :aggregate_failures do
      ['खोज अभियान जारी', 'लॉगिन समस्या से यूजर परेशान', 'सदस्यता अभियान शुरू', 'सहायता राशि जारी करने की मांग',
       'सर्च इंजन में बदलाव से कारोबारी परेशान', 'संपर्क करें तो मिलेगा मुआवजा',
       'और पढ़ें कैसे बढ़ें बच्चे', 'मेन्यू में बदलाव पर विवाद', 'हमारे बारे में बोले मुख्यमंत्री',
       'शेयर करें या नहीं बहस जारी', 'संबंधित खबरें हटाने की मांग पर सुनवाई'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year a headline, and a label with a bracketed count chrome', :aggregate_failures do
      ['संबंधित खबरें 2026', 'यह भी पढ़ें 2026', 'सदस्यता 2026', 'हमारे बारे में 2026', 'प्राइवेसी पॉलिसी 2026',
       'सब्सक्राइब करें 2026', 'नियम और शर्तें 2026'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
      expect(['संबंधित खबरें (3)', 'संबंधित खबरें [3]'].map { hi.recommended?(_1) }).to all(be(true))
      bare = ['सर्च 2', 'रजिस्टर 2', 'हमारे बारे में 2', 'संबंधित खबरें 3']
      expect(bare.map { hi.utility_chrome?(_1) }).to all(be(false))
    end

    it 'matches a term however its nukta letters are encoded, and holds every term in NFC', :aggregate_failures do
      precomposed = { "\u0915\u093C" => "\u0958", "\u0916\u093C" => "\u0959", "\u0917\u093C" => "\u095A",
                      "\u091C\u093C" => "\u095B", "\u0921\u093C" => "\u095C", "\u0922\u093C" => "\u095D",
                      "\u092B\u093C" => "\u095E", "\u092F\u093C" => "\u095F" }
      terms = described_class::Hi.terms.values.flatten.grep(String)
      expect(terms).to all(satisfy { _1 == _1.unicode_normalize(:nfc) })
      nukta = terms.grep(/\u093C/)
      expect(nukta).to include('और पढ़ें', 'न्यूज़लेटर')
      nukta.each do |term|
        forms = [term.unicode_normalize(:nfd), term.gsub(Regexp.union(precomposed.keys), precomposed)]
        forms.each { expect(hi.utility_chrome?(_1) || hi.read_more?(_1) || hi.recommended?(_1)).to be(true), _1 }
      end
    end

    it 'reads the labels on a Hindi page only, and the new-window notice', :aggregate_failures do
      [nil, :ja, :en, :zh, :ko].each { expect(text.call(_1).utility_chrome?('लॉगिन')).to be(false), _1.inspect }
      expect(hi.utility_chrome?('लॉगिन (नई विंडो में खुलता है)')).to be(true)
      expect(text.call(nil).utility_chrome?('लॉगिन (नई विंडो में खुलता है)')).to be(false)
    end

    it 'declares no type marker of its own', :aggregate_failures do
      expect(described_class::Hi.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:hi].type_markers).to eq(described_class.words(:type_marker))
    end
  end

  describe 'pager nouns' do
    let(:pager) do
      lambda do |label|
        element = Nokogiri::HTML("<html><body><nav aria-label=\"#{label}\"></nav></body></html>").at('nav')
        Html2rss::SST::Tags.chrome_scope(element, :sectioned, all_scope) == :chrome
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
        doc = Html2rss::SST::Normalizer.call(markup, vocabulary: all_scope)

        expect(doc.index.ignored_chrome?(doc.root.find { _1.name == :main }.children.first)).to be(chrome), label
      end
    end
  end

  describe 'Romanian labels' do
    let(:ro) { text.call(:ro) }
    let(:junk_reason) { ->(label) { Html2rss::AutoSource::Cleanup.junk_reason(label, vocabulary: described_class[:ro]) } }
    let(:readers) do
      {
        utility: ->(label) { ro.utility?(label) }, chrome: ->(label) { ro.utility_chrome?(label) },
        prefix: ->(label) { ro.utility_prefix?(label) }, recommended: ->(label) { ro.recommended?(label) },
        read_more: ->(label) { ro.read_more?(label) }, junk: ->(label) { !junk_reason.call(label).nil? }
      }
    end

    it 'reads chrome and recommended labels as whole labels, with a small count or wrapping marks',
       :aggregate_failures do
      ['Autentificare', 'Autentifică-te', 'Conectare', 'Contul meu', 'Deconectare', 'Căutare', 'Caută',
       'Despre noi', 'Contact', 'Politica de confidențialitate', 'Termeni și condiții', 'Politica de cookie-uri',
       'Meniu', 'Comentarii', 'Distribuie',
       'Sari la conținut'].each do |item|
        expect(ro.utility_chrome?(item)).to be(true), item
      end
      ['[Căutare]', '← Căutare ←', 'Autentificare (se deschide într-o fereastră nouă)',
       "\u200eCăutare\u200e"].each do |item|
        expect(ro.utility_chrome?(item)).to be(true), item
      end
      ['Articole similare', 'Știri conexe', 'Citește și', 'Te-ar putea interesa'].each do |item|
        expect(ro.recommended?(item)).to be(true), item
      end
    end

    it 'reads read-more and call-to-action labels as chrome and junk', :aggregate_failures do
      ['Citește mai mult', 'Citește articolul complet', 'Află mai multe', 'Citește tot articolul', 'Mai multe',
       'Mai mult', 'Vezi mai multe', 'Vezi mai mult'].each do |label|
        expect([ro.read_more?(label), junk_reason.call(label)]).to eq([true, :cta]), label
      end
      ['Abonează-te la newsletter', 'Abonează-te', 'Devino membru', 'Lasă un comentariu',
       'Distribuie articolul'].each do |item|
        expect(ro.utility_chrome?(item)).to be(true), item
      end
    end

    it 'reads the labels in upper case and in decomposed form', :aggregate_failures do
      ['AUTENTIFICARE', 'CONECTARE', 'CĂUTARE', 'DESPRE NOI', 'POLITICA DE CONFIDENȚIALITATE',
       'TERMENI ȘI CONDIȚII', 'SARI LA CONȚINUT'].each do |label|
        expect(ro.utility_chrome?(label)).to be(true), label
      end
      ['ABONEAZĂ-TE', 'ABONEAZĂ-TE LA NEWSLETTER', 'DEVINO MEMBRU'].each do |label|
        expect(ro.utility_chrome?(label)).to be(true), label
      end
      ['ARTICOLE SIMILARE', 'ȘTIRI CONEXE'].each { expect(ro.recommended?(_1)).to be(true), _1 }
      ['CITEȘTE MAI MULT', 'AFLĂ MAI MULTE'].each { expect(ro.read_more?(_1)).to be(true), _1 }
      ['Autentifică-te', 'Căutare', 'Termeni și condiții', 'Știri conexe'].each do |label|
        decomposed = label.unicode_normalize(:nfd)
        expect(decomposed).not_to eq(label)
        expect(ro.utility_chrome?(decomposed) || ro.recommended?(decomposed)).to be(true), label
      end
    end

    # Both spellings of s and t with a diacritic occur on real pages: comma-below (U+0219, U+021B) and the legacy
    # cedilla forms (U+015F, U+0163). The escapes keep the two spellings apart in the source.
    it 'reads the comma-below and the cedilla spelling of every label with a s or t', :aggregate_failures do
      ["Termeni \u0219i condi\u021Bii", "Termeni \u015Fi condi\u0163ii", "TERMENI \u0218I CONDI\u021AII",
       "TERMENI \u015EI CONDI\u0162II", "Politica de confiden\u021Bialitate", "Politica de confiden\u0163ialitate",
       "Sari la con\u021Binut", "Sari la con\u0163inut",
       "SARI LA CON\u0162INUT", "SARI LA CON\u021AINUT"].each do |label|
        expect(ro.utility_chrome?(label)).to be(true), label
      end
      ["\u0218tiri conexe", "\u015Etiri conexe", "\u015Ftiri recomandate", "\u0219tiri recomandate"].each do |label|
        expect(ro.recommended?(label)).to be(true), label
      end
      ["Distribuie \u0219tirea", "Distribuie \u015Ftirea", "Distribuie aceast\u0103 \u0219tire",
       "Distribuie aceast\u0103 \u015Ftire"].each do |label|
        expect(ro.utility_chrome?(label)).to be(true), label
      end
    end

    it 'keeps a headline that opens with or contains a label word a headline', :aggregate_failures do
      ['Autentificare dificilă la portalul primăriei, spun cetățenii', 'Căutare cu drone în pădurea din nord',
       'Contactul dintre delegații a fost reluat după o pauză lungă',
       'Conectare la internet gratuită în toate parcurile',
       'Meniu de sărbători mai scump cu un sfert', 'Despre noi și festivalul filmelor scurte',
       'Citește mai mult despre cetățenii care repară bănci', 'Abonează-te la lectură: biblioteca oferă cărți',
       'Vezi și revezi: expoziția foto s-a prelungit', 'Distribuie ajutoare un grup de voluntari',
       'Știri false circulă înainte de alegeri', 'Condiții grele de drum după prima ninsoare',
       'Mai multe locuri de parcare în centrul vechi', 'Vezi toate trenurile care circulă mâine',
       'Politica de confidențialitate a orașului, criticată de consilieri',
       'AUTENTIFICARE DIFICILĂ LA PORTALUL PRIMĂRIEI',
       'Cont nou pentru fiecare elev din clasa a cincea',
       'Citește și ascultă: cartea audio a fost lansată'].each do |headline|
        readers.each { |name, reader| expect(reader.call(headline)).to be(false), "#{name}: #{headline}" }
      end
    end

    it 'keeps a label followed by a year or a bare number a headline, and reads a bracketed count as chrome',
       :aggregate_failures do
      ['Meniu 2026', 'Căutare 2026', 'Articole similare 2026', 'Citește mai mult 2026', 'Autentificare 2026',
       'Termeni și condiții 2026', 'Mai multe 2026', 'ABONEAZĂ-TE 2026'].each do |label|
        readers.each_value { |reader| expect(reader.call(label)).to be(false), label }
      end
      ['Căutare [3]', 'Meniu (3)', 'Căutare (7)', 'Comentarii (12)'].each do |item|
        expect(ro.utility_chrome?(item)).to be(true), item
      end
      # `contact` keeps the shared reading: one trailing word plus a count, or a year, is chrome.
      ['Contact direct 12', 'Contact 2026'].each { expect(ro.utility_chrome?(_1)).to be(true), _1 }
      ['Vezi toate 12', 'Mai multe 3', 'Meniu 2', 'Comentarii 140'].each do |label|
        expect(ro.utility_chrome?(label)).to be(false), label
      end
    end

    it 'leaves out every section, pager and plausible-headline label', :aggregate_failures do
      %w[Politică Sport Externe Actualitate Economie Publicitate Abonare Înregistrare Detalii Redacția Acasă
         Anterior Următorul].each do |label|
        readers.each { |name, reader| expect(reader.call(label)).to be(false), "#{name}: #{label}" }
      end
    end

    # A "more" or "all" label that is chrome empties a card whose only other link it is (the heading is no link).
    # These are read-more labels, not chrome terms, so the card keeps its item.
    it 'reads an "all" or "more" label as read-more, not chrome, so a card with it as its only link keeps its item',
       :aggregate_failures do
      ['Vezi toate', 'Vezi toate articolele', 'Vezi toate știrile', 'Vezi mai multe știri', 'Toate articolele',
       'Toate știrile', 'Citește mai multe știri'].each do |label|
        readings = [ro.utility_chrome?(label), ro.recommended?(label), ro.read_more?(label)]
        expect(readings).to eq([false, false, true]), label
      end
    end

    it 'keeps every foreign ambiguous term reading as chrome on a Romanian page, and a longer headline a headline',
       :aggregate_failures do
      %w[Dela Teilen Plus Comment].each do |label|
        expect(ro.utility_chrome?(label)).to be(true), label
        expect(text.call(nil).utility_chrome?(label)).to be(true), label
      end
      ['Plus Piața Nouă s-a redeschis după două decenii', 'Dela Vale prelungește sezonul turistic'].each do |headline|
        expect(ro.utility_chrome?(headline)).to be(false), headline
        expect(ro.recommended?(headline)).to be(false), headline
        expect(ro.read_more?(headline)).to be(false), headline
      end
    end

    it 'reads the labels on a Romanian page only', :aggregate_failures do
      [nil, :ja, :en, :sv, :de, :vi].each do |code|
        expect(text.call(code).utility_chrome?('Autentificare')).to be(false), code.inspect
      end
    end

    it 'declares no type marker or path word of its own', :aggregate_failures do
      expect(described_class::Ro.terms.fetch(:type_marker)).to be_empty
      expect(described_class[:ro].type_markers).to eq(described_class.words(:type_marker))
      expect(described_class::SCOPED_WORDS.flat_map { described_class::Ro.terms.fetch(_1) }).to be_empty
    end

    it 'holds one Regexp per concept, not one per label', :aggregate_failures do
      %i[utility utility_cta read_more recommended new_window_notice].each do |concept|
        expect(described_class::Ro.terms.fetch(concept).size).to eq(1), concept
      end
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat
