# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Greek. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +el+, and nowhere else. Greek
    # inflects nouns and verbs ("Σύνδεση του δικτύου με την Κρήτη", "Εγγραφή μαθητών στα σχολεία"), so no term is read
    # as a prefix: each label is listed whole and read as a whole text only (no trailing word, no headline opener, see
    # {LinkDestination::TextClassifier}). Case folding handles final sigma (+ς+, +σ+, +Σ+) and an uppercase letter
    # with a tonos, but not an uppercase word written without tonos (+ΣΥΝΔΕΣΗ+ against +σύνδεση+), so each label with
    # a tonos is listed again without it; that second form reads a label in capitals and one typed without accents.
    # Only the concepts read through a {Scope} are listed (label words, the call to action, read-more and the
    # new-window notice); the others stay +NONE+ until their readers take the page scope. It lists no type marker
    # (stripping a short kicker could leave a headline below the title floor) and no section name (+Πολιτική+ is a
    # topic a feed may carry). A term whose precision is unclear is left out.
    El = Language.new(
      code: :el,
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
          'εγγραφή στο newsletter', 'εγγραφη στο newsletter', 'εγγραφείτε στο newsletter',
          'εγγραφειτε στο newsletter', 'εγγραφή στο ενημερωτικό δελτίο', 'εγγραφη στο ενημερωτικο δελτιο',
          'εγγραφείτε στο ενημερωτικό δελτίο', 'εγγραφειτε στο ενημερωτικο δελτιο', 'κάντε εγγραφή',
          'καντε εγγραφη', 'κάνε εγγραφή', 'κανε εγγραφη', 'κάντε συνδρομή', 'καντε συνδρομη',
          'κάνε συνδρομή', 'κανε συνδρομη', 'γίνε συνδρομητής', 'γινε συνδρομητης', 'γίνετε συνδρομητής',
          'γινετε συνδρομητης', 'κάντε εγγραφή τώρα', 'καντε εγγραφη τωρα', 'κάνε εγγραφή τώρα',
          'κανε εγγραφη τωρα', 'προσθήκη σχολίου', 'προσθηκη σχολιου', 'γράψτε σχόλιο', 'γραψτε σχολιο',
          'κοινοποιήστε', 'κοινοποιηστε', 'κοινοποίηση άρθρου', 'κοινοποιηση αρθρου'
        ],
        read_more: [
          'διαβάστε περισσότερα', 'διαβαστε περισσοτερα', 'διάβασε περισσότερα', 'διαβασε περισσοτερα',
          'δείτε περισσότερα', 'δειτε περισσοτερα', 'δες περισσότερα', 'δες περισσοτερα',
          'μάθετε περισσότερα', 'μαθετε περισσοτερα', 'μάθε περισσότερα', 'μαθε περισσοτερα',
          'περισσότερα', 'περισσοτερα', 'διαβάστε ολόκληρο το άρθρο', 'διαβαστε ολοκληρο το αρθρο',
          'διαβάστε όλο το άρθρο', 'διαβαστε ολο το αρθρο', 'ολόκληρο το άρθρο', 'ολοκληρο το αρθρο',
          'συνέχεια ανάγνωσης', 'συνεχεια αναγνωσης', 'συνεχίστε την ανάγνωση', 'συνεχιστε την αναγνωση',
          'δείτε όλο το άρθρο', 'δειτε ολο το αρθρο', 'διαβάστε το άρθρο', 'διαβαστε το αρθρο'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          /(?:ανο(?:ί|ι)γει\s+σε\s+)?ν(?:έ|ε)(?:ο|α)\s+(?:παράθυρο|παραθυρο|καρτέλα|καρτελα)/
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
          'σύνδεση', 'συνδεση', 'αποσύνδεση', 'αποσυνδεση', 'εγγραφή', 'εγγραφη', 'εγγραφείτε',
          'εγγραφειτε', 'συνδεθείτε', 'συνδεθειτε', 'αναζήτηση', 'αναζητηση', 'επικοινωνία', 'επικοινωνια',
          'συνδρομή', 'συνδρομη', 'συνδρομές', 'συνδρομες', 'σχόλια', 'σχολια', 'μενού', 'μενου',
          'ειδοποιήσεις', 'ειδοποιησεις', 'newsletter', 'όροι χρήσης', 'οροι χρησης',
          'όροι και προϋποθέσεις', 'οροι και προυποθεσεις', 'οροι και προϋποθεσεις',
          'πολιτική απορρήτου', 'πολιτικη απορρητου',
          'πολιτική cookies', 'πολιτικη cookies', 'πολιτική προστασίας προσωπικών δεδομένων',
          'πολιτικη προστασιας προσωπικων δεδομενων', 'πολιτική προστασίας δεδομένων',
          'πολιτικη προστασιας δεδομενων', 'σχετικά με εμάς', 'σχετικα με εμας', 'χάρτης ιστότοπου',
          'χαρτης ιστοτοπου', 'διαφημιστείτε μαζί μας', 'διαφημιστειτε μαζι μας', 'ρυθμίσεις cookies',
          'ρυθμισεις cookies', 'ρυθμίσεις απορρήτου', 'ρυθμισεις απορρητου'

        ],
        recommended: [
          'προτεινόμενα', 'προτεινομενα', 'προτεινόμενα άρθρα', 'προτεινομενα αρθρα',
          'προτεινόμενες ειδήσεις', 'προτεινομενες ειδησεις', 'σχετικά άρθρα', 'σχετικα αρθρα',
          'σχετικά θέματα', 'σχετικα θεματα', 'σχετικές ειδήσεις', 'σχετικες ειδησεις', 'διαβάστε επίσης',
          'διαβαστε επισης', 'δείτε επίσης', 'δειτε επισης', 'διαβάστε ακόμα', 'διαβαστε ακομα',
          'δείτε ακόμα', 'δειτε ακομα', 'μπορεί να σας ενδιαφέρουν', 'μπορει να σας ενδιαφερουν',
          'μπορεί να σας ενδιαφέρει', 'μπορει να σας ενδιαφερει'

        ]
      }.freeze
    )
  end
end
