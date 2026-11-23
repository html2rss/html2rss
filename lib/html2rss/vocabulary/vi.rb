# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Vietnamese. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +vi+, and nowhere else.
    # Vietnamese writes one syllable per word, so a label is a short phrase of ordinary words ("tìm kiếm", "chia sẻ",
    # "liên hệ") that also open headlines. No term is read as a prefix or a substring: each label is listed whole and
    # read as a whole text only (no trailing word, no headline opener, see {LinkDestination::TextClassifier}). Terms
    # are written in NFC, the form the classifier normalizes to, so decomposed input matches and upper case
    # ("ĐĂNG NHẬP") folds. Only the concepts read through a {Scope} are listed (label words, the call to action,
    # read-more, recommended and the new-window notice); the others stay +NONE+ until their readers take the page
    # scope. It lists no type marker (stripping a short kicker could leave a headline below the title floor), no
    # section name (+thế giới+, +thể thao+ and +kinh doanh+ are topics a feed may carry), no pager label, no path
    # word, and no label that is also a plausible short headline (+quảng cáo+ is advertising, +giới thiệu+ an
    # introduction, +chi tiết+ a detail, +hủy bỏ+ a cancellation, +tin khác+ other news). A term whose precision is
    # unclear is left out.
    Vi = Language.new(
      code: :vi,
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
          'đăng ký nhận bản tin', 'đăng ký nhận tin', 'đăng ký bản tin', 'đăng ký ngay',
          'đăng ký nhận bản tin miễn phí', 'đăng ký thành viên', 'đăng ký tài khoản', 'gửi bình luận',
          'viết bình luận', 'bình luận ngay', 'chia sẻ bài viết', 'chia sẻ bài này'
        ],
        read_more: [
          'đọc tiếp', 'đọc thêm', 'xem tiếp', 'xem chi tiết', 'đọc toàn bộ bài viết', 'xem toàn bộ bài viết',
          'đọc tiếp bài viết', 'đọc bài viết', 'xem bài viết'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'mở trong tab mới', 'mở trong cửa sổ mới', 'mở trong thẻ mới', 'mở ở tab mới', 'mở ở cửa sổ mới',
          'mở cửa sổ mới', 'mở tab mới'
        ],
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
          'đăng nhập', 'đăng xuất', 'đăng ký', 'tạo tài khoản', 'tìm kiếm', 'về chúng tôi', 'liên hệ',
          'liên hệ quảng cáo', 'liên hệ tòa soạn', 'liên hệ toà soạn', 'thông tin tòa soạn',
          'chính sách bảo mật', 'chính sách quyền riêng tư', 'chính sách cookie', 'điều khoản sử dụng',
          'điều khoản dịch vụ', 'điều khoản và điều kiện', 'trang chủ', 'menu', 'xem thêm', 'xem tất cả',
          'xem toàn bộ', 'bình luận', 'chia sẻ', 'tải ứng dụng', 'đặt báo', 'bỏ qua đến nội dung chính',
          'chuyển đến nội dung chính', 'chuyển đến nội dung'
        ],
        recommended: [
          'tin liên quan', 'bài liên quan', 'bài viết liên quan', 'tin cùng chuyên mục', 'bài viết khác',
          'có thể bạn quan tâm', 'bạn có thể quan tâm', 'có thể bạn cũng quan tâm', 'bạn có thể thích',
          'đề xuất cho bạn', 'gợi ý cho bạn'
        ]
      }.freeze
    )
  end
end
