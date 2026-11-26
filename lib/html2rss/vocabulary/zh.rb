# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Chinese, Simplified and Traditional in one list (+zh-Hans+, +zh-Hant+, +zh-CN+, +zh-TW+ are +zh+). It is
    # {PAGE_ONLY}: its terms apply on a page whose language resolves to +zh+, and nowhere else. Han text has no
    # word boundary and a headline may open with any label word, so a label term is read as a whole text only (no
    # trailing word, no headline opener, see {AutoSource::LinkDestination::TextClassifier}). Only the concepts read
    # through a
    # {Scope} are listed (path words, label words, the call to action and read-more); the others stay +NONE+ until
    # a term of clear precision is added. A term whose precision is unclear is left out.
    Zh = Language.new(
      code: :zh,
      terms: {
        path_section: NONE,
        path_article: NONE,
        path_profile: NONE,
        path_office: NONE,
        path_non_article: NONE,
        path_taxonomy: NONE,
        path_vanity: NONE,
        path_soft_utility: NONE,
        path_chrome: NONE,
        path_media: NONE,
        path_deep_post_context: NONE,
        utility_prefix: NONE,
        utility_cta: %w[
          订阅电子报 訂閱電子報 订阅我们的电子报 訂閱我們的電子報 免费订阅 免費訂閱 立即订阅 立即訂閱 立即注册 立即註冊
        ],
        read_more: %w[
          阅读全文 閱讀全文 阅读更多 閱讀更多 阅读原文 閱讀原文 点击阅读全文 點擊閱讀全文 继续阅读 繼續閱讀 查看全文 了解更多 瞭解更多
        ],
        list_more: %w[查看全部 查看更多 更多],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: NONE,
        paid_label: NONE,
        ad_word: NONE,
        field_label: NONE,
        type_label: NONE,
        pager_label: NONE,
        page_link: NONE,
        page_link_label: NONE,
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: NONE,
        podcast_unspaced: NONE,
        type_marker: NONE,
        utility: %w[
          关于我们 關於我們 联系我们 聯絡我們 联络我们 评论 登录 登入 注册 註冊 订阅 訂閱 分享 搜索 搜尋 电子报 電子報 隐私政策 隱私政策 隱私權政策 使用条款 使用條款 服务条款 服務條款 帮助 幫助 留言
        ],
        recommended: %w[推荐阅读 推薦閱讀 相关阅读 相關閱讀 延伸阅读 延伸閱讀 猜你喜欢 猜你喜歡 为您推荐 為您推薦]
      }.freeze,
      # Japanese title type markers that are also ordinary Chinese words, so a Chinese page reads them as text:
      # +独自+ is "independent, own" (+独自开发+) and +写真+ is "portrait, photo shoot" (+写真集+), the same character
      # forms in Simplified Chinese. +速報+ and +詳報+ read as the same breaking/detailed-report tags in Traditional
      # Chinese; +動画+, +中継+ and +生中継+ are no Chinese spelling (+动画+, +中继+). Chinese lists no marker of its
      # own: stripping a short Han kicker leaves a headline below the title floor.
      plain_words: Set['独自', '写真'].freeze
    )
  end
end
