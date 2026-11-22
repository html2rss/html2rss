# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Chinese, Simplified and Traditional in one list (+zh-Hans+, +zh-Hant+, +zh-CN+, +zh-TW+ are +zh+). Han text
    # has no word boundary, so a term only matches as a whole label or before whitespace or punctuation (Ruby's
    # +\b+ does not separate two Han characters); a form that is also an ordinary Japanese word is flagged
    # ambiguous so it applies on Chinese and unlabeled pages only. A term whose precision is unclear is left out.
    Zh = Language.new(
      code: :zh,
      terms: {
        # No Han path segment occurs on the saved Chinese pages (their paths are Latin or numeric), so no path
        # word is listed; the Latin words every language shares read them.
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
        type_marker: %w[快讯 快訊 独家 獨家 视频 視頻 图集 圖集 直播],
        utility_prefix: %w[查看全部 查看更多 查看所有 订阅 訂閱 注册 註冊],
        utility: %w[
          关于我们 關於我們 联系我们 聯絡我們 聯繫我們 联络我们 评论 登录 登入 注册 註冊 订阅 訂閱 分享 搜索 搜尋
          查看全部 查看更多 更多 电子报 電子報 隐私政策 隱私政策 隱私權政策 使用条款 使用條款 服务条款 服務條款 帮助 幫助
          留言
        ],
        recommended: %w[推荐阅读 推薦閱讀 相关阅读 相關閱讀 延伸阅读 延伸閱讀 猜你喜欢 猜你喜歡 为您推荐 為您推薦],
        utility_cta: [
          # Each ends at a boundary ({TextClassifier}); the comment labels end at the end of the text, so a headline
          # that opens with one ("发表评论：...") is no label unless nothing follows.
          /订阅(?:我们的)?(?:电子报|电子邮件|新闻通讯)/, /訂閱(?:我們的)?(?:電子報|電子郵件|新聞通訊)/,
          '立即订阅', '立即訂閱', '立即注册', '立即註冊', '免费订阅', '免費訂閱',
          /(?:发表评论|發表評論|發表留言)(?=\s*\z)/, /登录后(?:发表)?评论/, /登入後(?:發表)?(?:評論|留言)/
        ],
        read_more: %w[
          阅读全文 閱讀全文 阅读更多 閱讀更多 阅读原文 閱讀原文 查看全文 查看详情 查看詳情 查看更多 了解更多
          瞭解更多 详细内容 詳細內容 详情 詳情 点击阅读 點擊閱讀 全文
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/(?:在)?新(?:窗口|视窗|視窗|标签页|標籤頁|分頁|頁籤)(?:中)?(?:打开|打開|開啟)/],
        paid_label: %w[赞助内容 贊助內容 推广内容 推廣內容 商业合作 商業合作 广告合作 廣告合作 業配文],
        ad_word: %w[广告 廣告],
        field_label: %w[栏目 欄目 类别 類別 分类 分類 专题 專題 主题],
        type_label: %w[文章类型 文章類型 内容类型 內容類型 稿件类型 稿件類型],
        pager_label: %w[分页 分頁 分页导航 分頁導航],
        page_link: NONE,
        page_link_label: %w[
          上一页 下一页 上一頁 下一頁 上一篇 下一篇 上页 下页 上頁 下頁 较早 較早 较新 較新 旧文章 舊文章 新文章
        ],
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: NONE,
        podcast_unspaced: %w[播客]
      }.freeze,
      ambiguous: {
        utility: %w[留言]
      }.freeze
    )
  end
end
