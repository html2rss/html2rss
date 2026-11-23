# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Korean. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +ko+, and nowhere else. Korean
    # attaches particles and endings to nouns ("로그인 오류로", "구독 경제가"), so no term is read as a prefix: each
    # label form is listed whole, with and without its inner space, and read as a whole text only (no trailing word,
    # no headline opener, see {LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed
    # (label words, the call to action, read-more and the new-window notice); the others stay +NONE+ until their
    # readers take the page scope. It lists no type marker (stripping a short kicker could leave a headline below the
    # title floor) and no section name (+정치+, +사회+ and +스포츠+ are topics a feed may carry). A term whose
    # precision is unclear is left out.
    Ko = Language.new(
      code: :ko,
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
        utility_cta: [
          '구독하기', '지금 구독하기', '뉴스레터 구독', '뉴스레터 구독하기', '뉴스레터 신청', '뉴스레터 신청하기', '무료 구독', '무료 구독하기', '구독 신청', '구독신청',
          '신문 구독', '신문구독', '회원가입하기', '로그인하기', '댓글 쓰기', '댓글쓰기', '공유하기'
        ],
        read_more: [
          '기사 전문 보기', '기사 전문보기', '전문 보기', '전문보기', '원문 보기', '원문보기', '자세히 보기', '자세히보기', '기사 더보기', '계속 읽기', '더 읽기',
          '더 알아보기'
        ],
        list_more: ['더보기'],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/새\s*(?:창|탭)(?:에서|으로)?\s*(?:열기|열림)/],
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
        utility: [
          '로그인', '로그아웃', '회원가입', '검색', '이용약관', '개인정보처리방침', '개인정보 처리방침', '개인정보취급방침', '개인정보 취급방침', '청소년보호정책', '청소년 보호정책',
          '회사소개', '회사 소개', '광고안내', '광고 안내', '사이트맵', '고객센터', '뉴스레터', '구독', '마이페이지', '닫기', '공유', '댓글', '사업제휴', '고충처리',
          '전체메뉴', '본문 바로가기', '문의하기', '도움말'
        ],
        recommended: [
          '추천기사', '추천 기사', '관련기사', '관련 기사', '추천 뉴스', '함께 볼만한 기사', '함께 볼 만한 기사',
          '함께 보면 좋은 기사', '이 기사와 함께 읽으면 좋은 기사'
        ]
      }.freeze
    )
  end
end
