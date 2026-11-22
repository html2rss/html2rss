# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Japanese.
    Ja = Language.new(
      code: :ja,
      terms: {
        path_section: %w[ニュース 記事 お知らせ ブログ],
        path_article: %w[記事 投稿],
        path_profile: %w[著者 執筆者 記者 ライター],
        path_office: %w[編集部],
        path_non_article: %w[ゲーム クイズ 星座占い 占い 訃報 おくやみ ライブ配信],
        path_taxonomy: %w[カテゴリ カテゴリー タグ テーマ],
        path_vanity: %w[会員登録 新規登録 購読 プレミアム 有料会員],
        path_soft_utility: %w[おすすめ 会員 メルマガ ニュースレター],
        path_chrome: %w[
          会社概要 お問い合わせ 検索 ログイン プライバシーポリシー 利用規約 ヘルプ アーカイブ プロフィール
          アカウント 設定 コメント
        ],
        path_media: %w[動画 ビデオ ポッドキャスト 音声],
        path_deep_post_context: %w[プレスリリース ニュースリリース 報道発表],
        type_marker: %w[速報 詳報 独自 動画 写真 中継 生中継 ライブ プレスリリース],
        utility_prefix: %w[すべて見る 全て見る ニュースレター メルマガ 会員登録 購読],
        utility: %w[
          会社概要 お問い合わせ コメント ログイン 会員登録 新規登録 シェア 共有 購読 すべて見る 全て見る
          もっと見る ニュースレター メルマガ
        ],
        recommended: %w[おすすめ],
        utility_cta: %w[
          ニュースレターを購読 ニュースレターに登録 メルマガを購読 メルマガに登録 コメントを投稿 コメントを書く
          ログインしてコメント お問い合わせはこちら この記事をシェア この記事を共有 会員登録はこちら
        ],
        read_more: %w[続きを読む もっと読む 続きはこちら 詳しくはこちら 詳細を見る 詳細はこちら 全文を読む 続きを見る],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: [/の続きを読む/, /をもっと読む/, /について詳しく(?:はこちら)?/, /の詳細(?:を見る|はこちら)/],
        new_window_notice: [/新しい(?:ウィンドウ|ウインドウ|タブ)で開く/],
        paid_label: [/タイアップ(?:広告|企画)?/, /スポンサー(?:リンク|コンテンツ)/, '広告企画', 'PR企画'],
        ad_word: %w[広告 スポンサー],
        field_label: ['セクション', /カテゴリー?/, 'ジャンル', '分類', '記事'],
        type_label: %w[記事の種類 記事タイプ コンテンツの種類],
        pager_label: [/ページネーション/, /ページ送り/, /ページナビゲーション/],
        page_link: NONE,
        page_link_label: %w[前へ 次へ 前 次 前のページ 次のページ 前のページへ 次のページへ 前の記事 次の記事 古い記事 新しい記事],
        clock_suffix: NONE,
        date_piece: [/(?:\d{4}年)?\d{1,2}月\d{1,2}日/],
        element_label: %w[PR],
        podcast_word: NONE,
        podcast_unspaced: %w[ポッドキャスト エピソード]
      }.freeze,
      ambiguous: {
        path_taxonomy: %w[テーマ]
      }.freeze
    )
  end
end
