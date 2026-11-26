# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Thai. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +th+, and nowhere else. Thai
    # writes no spaces between words, so a label word can sit at the start or inside the middle of a headline
    # (+ค้นหาผู้รอดชีวิต+, +ดูเพิ่มเติมได้ที่+). No term is read as a prefix or a substring: each label is listed
    # whole, read as a whole text only (no trailing word, no headline opener, see {AutoSource::LinkDestination::TextClassifier}).
    # Only the concepts read through a {Scope} are listed (label words, the call to action, read-more, recommended
    # and the new-window notice); the others stay +NONE+ until their readers take the page scope. It lists no type
    # marker (stripping a short kicker could leave a headline below the title floor), no section name
    # (+การเมือง+, +กีฬา+ and +ข่าว+ are topics a feed may carry), no pager label, and no label that is also a plausible
    # short headline (+ความคิดเห็น+ is the opinion section, +ยอดนิยม+ a ranking). A term whose precision is unclear
    # is left out.
    Th = Language.new(
      code: :th,
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
          สมัครรับจดหมายข่าว สมัครรับข่าวสาร สมัครรับจดหมายข่าวของเรา ลงทะเบียนรับจดหมายข่าว สมัครสมาชิกวันนี้
          สมัครสมาชิกเลย แสดงความคิดเห็น ร่วมแสดงความคิดเห็น เขียนความคิดเห็น แชร์บทความนี้ แชร์ข่าวนี้
        ],
        read_more: %w[
          อ่านต่อ อ่านต่อที่นี่ อ่านเพิ่มเติม อ่านข่าวต่อ อ่านรายละเอียด อ่านบทความเต็ม อ่านข่าวเต็ม อ่านข่าวฉบับเต็ม
          ดูรายละเอียด ดูรายละเอียดเพิ่มเติม รายละเอียดเพิ่มเติม
        ],
        list_more: %w[ดูเพิ่มเติม ดูเพิ่ม ดูทั้งหมด เพิ่มเติม],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/เปิด(?:ใน)?\s*(?:หน้าต่าง|แท็บ|แถบ)\s*ใหม่/],
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
          เข้าสู่ระบบ ลงชื่อเข้าใช้ ออกจากระบบ ลงชื่อออก สมัครสมาชิก ลงทะเบียน ค้นหา เกี่ยวกับเรา ติดต่อเรา ติดต่อโฆษณา
          ร่วมงานกับเรา นโยบายความเป็นส่วนตัว นโยบายคุกกี้ นโยบายการใช้คุกกี้ ตั้งค่าคุกกี้ การตั้งค่าคุกกี้
          ข้อกำหนดและเงื่อนไข ข้อตกลงและเงื่อนไข ข้อกำหนดการใช้งาน ข้อตกลงการใช้งาน เงื่อนไขการใช้งาน
          เงื่อนไขการให้บริการ แผนผังเว็บไซต์ แผนผังเว็บไซท์ จดหมายข่าว คำถามที่พบบ่อย ศูนย์ช่วยเหลือ ช่วยเหลือ เมนู
          หน้าแรก แชร์ ข้ามไปยังเนื้อหา
        ],
        recommended: %w[
          ข่าวที่เกี่ยวข้อง บทความที่เกี่ยวข้อง เรื่องที่เกี่ยวข้อง ข่าวแนะนำ บทความแนะนำ
          บทความที่คุณอาจสนใจ คุณอาจสนใจ อ่านด้วย
        ]
      }.freeze
    )
  end
end
