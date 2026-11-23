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
      kind = Html2rss::LinkDestination::Sponsorship::LabelText.method(:kind)

      expect(kind.call('Conteúdo patrocinado por Marca')).to eq(:paid_label)
      expect(kind.call('Publieditorial')).to eq(:paid_label)
      expect(kind.call('Publicidade')).to eq(:label)
      title = Html2rss::Article::Title.compose('Porto reabre', kicker: 'Seção: Transportes')

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

  describe 'Chinese labels' do
    let(:labels) do
      %w[关于我们 關於我們 联系我们 聯絡我們 登录 登入 注册 註冊 订阅 訂閱 分享 搜索 搜尋 更多 查看更多 隐私政策
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
      ['登录 (3)', '[订阅]', '→ 更多 →', '更多 (12)'].each { expect(zh.utility_chrome?(_1)).to be(true), _1 }
      %w[推荐阅读 推薦閱讀 相关阅读 相關閱讀 猜你喜欢 猜你喜歡].each { expect(zh.recommended?(_1)).to be(true), _1 }
    end

    it 'reads a bracketed count after a Chinese label as chrome, a bare number as a headline', :aggregate_failures do
      expect(['更多 (12)', '相关阅读 [3]', '隐私政策 （2）'].map { zh.utility_chrome?(_1) }).to all(be(true))
      expect(['更多 12', '相关阅读 3', '隐私政策 2'].map { zh.utility_chrome?(_1) }).to all(be(false))
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
      %w[로그인 로그아웃 회원가입 검색 이용약관 개인정보처리방침 회사소개 사이트맵 고객센터 뉴스레터 구독 더보기 닫기 공유
         댓글].each { expect(ko.utility_chrome?(_1)).to be(true), _1 }
      ['개인정보 처리방침', '본문 바로가기', '로그인 (3)', '[더보기]', '→ 더보기 →'].each { expect(ko.utility_chrome?(_1)).to be(true), _1 }
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
      ['התחברות', 'תנאי שימוש', 'מדיניות הפרטיות', 'צרו קשר', 'אודות', 'מפת האתר',
       'הצהרת נגישות', 'דלג לתוכן', 'התחברות (3)', '[צרו קשר]', '→ אודות →'].each do |label|
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
      expect(he.utility_chrome?('התחברות (12)')).to be(true)
      expect(he.utility_chrome?('התחברות 12')).to be(false)
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

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat
