# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::Sponsorship do
  let(:node) do
    lambda do |name: :span, text: 'x', class_names: nil, raw: nil, style: nil, children: nil|
      attrs = Html2rss::SST::Attrs.build(class_names:, raw:, style:)
      Html2rss::SST::Node.build(name:, own_text: text, attrs:, children:)
    end
  end
  let(:marker) { ->(element, ancestors = []) { described_class.marker(element, ancestors) } }
  let(:label) { ->(text, **opts) { marker[node[text:, **opts]] } }
  let(:block) { node[name: :div, text: ''] }
  let(:paid_phrases) do
    ['Gesponsert', 'Sponsored content', 'Paid post', 'Paid content', 'Partner content', 'Advertorial',
     'Promoted', 'Contenu sponsorisé', 'Publireportage', 'Contenus partenaires', 'Contenu partenaire',
     'Contenido patrocinado', 'Publirreportaje', '· Sponsored story ·', 'Sponsorizzato',
     'Contenuto sponsorizzato', 'Informazione pubblicitaria', 'Pubbliredazionale', 'Gesponsord',
     'Gesponsorde inhoud', 'Sponsorowane', 'Materiał Partnera', 'MATERIAŁ PROMOCYJNY', 'Materiał partnerski',
     'Materiały promocyjne', 'Artykuł sponsorowany', 'Sponsrat innehåll', 'Annonssamarbete', '提供',
     'タイアップ', 'スポンサーリンク', '広告企画', 'PR企画']
  end

  describe '.marker' do
    it 'marks a rel containing sponsored in any case and position as a container', :aggregate_failures do
      expect(marker[node[name: :a, raw: { 'rel' => 'sponsored' }]]).to eq(:container)
      expect(marker[node[name: :a, raw: { 'rel' => 'nofollow Sponsored' }]]).to eq(:container)
      expect(marker[node[name: :a, raw: { 'rel' => "nofollow\tsponsored" }]]).to eq(:container)
      expect(marker[node[name: :a, raw: { 'rel' => 'nofollow noopener' }]]).to be_nil
      expect(marker[node[name: :a, raw: { 'rel' => 'sponsoredx' }]]).to be_nil
    end

    it 'marks advertorial attributes only for a closed set of truthy values', :aggregate_failures do
      on = ['true', 'TRUE', '1', 'yes', ' Yes ']
      off = ['', 'no', 'null', 'false', 'False', '0', 'off', 'acme']
      expect(on.map { marker[node[raw: { 'data-sponsored' => _1 }]] }).to all(eq(:container))
      expect(off.map { marker[node[raw: { 'data-advertorial' => _1 }]] }).to all(be_nil)
      expect(marker[node[raw: { 'data-ad-slot' => 'true' }]]).to be_nil
    end

    it 'marks sponsored class tokens whole or as BEM and state variants' do
      tokens = %w[advertorial sponsored is-sponsored is-advertorial sponsored-content card--sponsored
                  teaser--advertorial c-card__sponsored sponsored_post]
      expect(tokens.map { marker[node[class_names: ['card', _1]]] }).to all(eq(:container))
    end

    it 'marks native-advertising class tokens whole, as BEM modifiers, or as native-ad blocks' do
      tokens = %w[native teaser--native card__native native-ad native-ads adv-native adv-native-strip ad-native
                  teaser__native-ad-bar]
      expect(tokens.map { marker[node[class_names: ['card', _1]]] }).to all(eq(:container))
    end

    it 'ignores native look-alike class tokens' do
      rejected = %w[--native native-input nativeApp native-teaser bt-langnative ep_field-native native-teaser-image
                    adv-native-strip__card adv-native-strip--multi Native]
      expect(rejected.filter_map { marker[node[class_names: [_1]]] }).to be_empty
    end

    it 'ignores sponsored look-alike class tokens' do
      rejected = %w[unsponsored non-sponsored page-sponsored sponsored-by-line sponsoredx Sponsored card--sponsor
                    has-sponsored has-advertorial list--has-sponsored]
      expect(rejected.filter_map { marker[node[class_names: [_1]]] }).to be_empty
    end

    it 'marks ad-label class tokens as labels, without label text' do
      tokens = %w[ad-label ad-labels ad-labels__item ad-badge ad-marker ad-label--small]
      expect(tokens.map { marker[node[class_names: ['teaser__meta', _1]]] }).to all(eq(:label))
    end

    it 'ignores ad-slot and look-alike class tokens' do
      rejected = %w[ad-container ad-tag-container adress head shadow badge ad-labeled teaser__ad-labels
                    ad-label__ ad-labelsx Ad-label]
      expect(rejected.filter_map { marker[node[class_names: [_1]]] }).to be_empty
    end

    it 'ignores class markers on empty or hidden elements' do
      hidden = [{ text: ' ' }, { text: '', class_names: %w[sponsored] }, { class_names: %w[d-none] },
                { style: 'color: red; display : none' }, { raw: { 'hidden' => '' } },
                { raw: { 'hidden' => '1' }, class_names: %w[sponsored] }]
      expect(hidden.filter_map { marker[node[**_1, class_names: ['ad-label', *_1[:class_names]]]] }).to be_empty
    end

    it 'keeps class markers on visible elements with text or children', :aggregate_failures do
      expect(marker[node[raw: { 'aria-hidden' => 'true' }, class_names: %w[ad-label]]]).to eq(:label)
      expect(marker[node[style: 'color: red', class_names: %w[ad-label]]]).to eq(:label)
      expect(marker[node[text: '', class_names: %w[ad-labels], children: [node[]]]]).to eq(:label)
    end

    it 'never reads paywall markers as sponsorship' do
      paywall = [{ 'data-paid-category' => 'plus' }, { 'data-testid' => 'paid-teaser' },
                 { 'data-tracking-paid-category' => 'paid' }]
      expect(paywall.filter_map { marker[node[raw: _1, class_names: %w[paywall-badge plus-badge]]] }).to be_empty
    end

    it 'marks ARIA labels that are exactly an ad label as containers', :aggregate_failures do
      expect(marker[node[raw: { 'aria-label' => 'Anzeige' }]]).to eq(:container)
      expect(marker[node[raw: { 'aria-roledescription' => 'Advertisement' }]]).to eq(:container)
      expect(marker[node[raw: { 'aria-label' => 'Read the story about advertising' }]]).to be_nil
    end

    it 'marks element text that is exactly an ad word or a paid phrase, but never anchor text', :aggregate_failures do
      expect(label[' Werbung ']).to eq(:label)
      expect(label['[Sponsored]', name: :p]).to eq(:paid_label)
      expect(label['Sponsored', name: :a]).to be_nil
      expect(label['Advertising']).to be_nil
    end

    it 'reads a heading only when its whole text is a paid phrase', :aggregate_failures do
      expect(label['Sponsored content', name: :h2]).to eq(:paid_label)
      expect(label['Anzeige', name: :h4]).to be_nil
      expect(label['Werbung', name: :h2]).to be_nil
    end

    it 'ignores text labels on unrendered elements', :aggregate_failures do
      expect(label['Anzeige', raw: { 'hidden' => '' }]).to be_nil
      expect(label['Anzeige', style: 'display:none']).to be_nil
      expect(%w[hidden d-none is-hidden hide].filter_map { label['Anzeige', class_names: ['label', _1]] }).to be_empty
    end

    it 'ignores text and class labels under a hidden ancestor inside their card', :aggregate_failures do
      chains = [{ class_names: %w[d-none] }, { raw: { 'hidden' => '' } }, { style: 'display: none' }]
               .map { [node[name: :article, text: ''], node[name: :div, text: '', **_1]] }
      expect(chains.filter_map { marker[node[text: 'Anzeige'], [*_1, block]] }).to be_empty
      expect(chains.filter_map { marker[node[class_names: %w[ad-label]], _1] }).to be_empty
      expect(chains.filter_map { marker[node[class_names: %w[is-sponsored]], _1] }).to be_empty
    end

    it 'keeps labels whose hidden ancestor sits outside their card', :aggregate_failures do
      panel = node[name: :div, text: '', class_names: %w[hidden]]
      %i[article section aside li].each do |card|
        expect(marker[node[text: 'Anzeige'], [panel, node[name: card, text: ''], block]]).to eq(:label)
      end
      expect(marker[node[class_names: %w[ad-label]], [panel, node[name: :li, text: '']]]).to eq(:label)
    end

    it 'keeps visual-only and screen-reader-only text labels', :aggregate_failures do
      expect(label['Anzeige', raw: { 'aria-hidden' => 'true' }]).to eq(:label)
      expect(label['Sponsored', class_names: %w[sr-only]]).to eq(:paid_label)
      expect(label['Anzeige', class_names: %w[label hidden-xs]]).to eq(:label)
    end

    it 'marks the closed multilingual ad words with surrounding punctuation or separators' do
      labels = ['Anzeige', 'Ad', 'AD:', 'Advertisement', 'Publicité:', 'Publicidad', 'Pubblicità', 'Advertentie',
                'Reclame', 'Reklama', 'REKLAMA', 'Annons', 'Reklam', '広告', '【広告】', 'スポンサー', 'Anzeige |',
                'Anzeige ·', 'Anzeige •', 'Anzeige /', "Anzeige\u00A0|"]
      expect(labels.reject { label[_1] == :label }).to be_empty
    end

    it 'marks the closed multilingual paid phrases' do
      expect(paid_phrases.reject { label[_1] == :paid_label }).to be_empty
    end

    it 'marks paid attribution naming a sponsor in up to five words' do
      labels = ['Sponsored by Acme Heating', 'Gesponsert von Acme', 'Sponsorisé par Acme', 'Patrocinado por Acme Hogar',
                'Sponsored by a b c d e', 'Sponsored by', 'Contenuto sponsorizzato a cura di Acme Studio',
                'Sponsorizzato da Acme', 'Gesponsord door Acme', '提供：アクメ株式会社']
      expect(labels.reject { label[_1] == :paid_label }).to be_empty
    end

    it 'marks PR only as a whole uppercase element text', :aggregate_failures do
      expect(label['PR']).to eq(:label)
      expect(label['【PR】']).to eq(:label)
      expect([label['Pr'], label['pr'], label['PR agency']]).to all(be_nil)
      expect(marker[node[raw: { 'aria-label' => 'PR' }]]).to be_nil
      expect(label['PR', class_names: %w[tag]]).to be_nil
    end

    it 'ignores attribution that states no payment' do
      rejected = ['Presented by Acme', 'Präsentiert von Acme', 'In Kooperation mit Acme', 'En partenariat avec Acme',
                  'In partnership with Acme', 'proposé par Acme', 'In collaborazione con Acme',
                  'In samenwerking met Acme', 'I samarbete med Acme', 'Partenaires', 'Partners']
      expect(rejected.filter_map { label[_1] }).to be_empty
    end

    it 'ignores text that only contains or starts with a label' do
      rejected = ['Advertising', 'Anzeigenmarkt', 'Adventure', 'Ad hoc', 'Sponsored posts dominate the feed',
                  'Sponsored by a b c d e f', 'Paid', 'Partner', 'Werbung im Wandel', 'by Acme']
      expect(rejected.filter_map { label[_1] }).to be_empty
    end

    it 'reads the whole element text, so a label word beside other text is no label', :aggregate_failures do
      meta_line = node[name: :div, text: ' · Werbung', children: [node[name: :time, text: '10.11.2026']]]
      expect(marker[meta_line]).to be_nil
      expect(marker[node[name: :div, text: '', children: [node[text: 'Anzeige']]]]).to be_nil
    end

    it 'ignores ad words on topic chips, but reads paid phrases there', :aggregate_failures do
      chips = %w[category Post-Category tag tags__item kicker teaser__kicker topic eyebrow rubrik]
      expect(chips.filter_map { marker[node[text: 'Werbung', class_names: [_1]]] }).to be_empty
      expect(marker[node[text: 'Werbung', class_names: %w[tagline]]]).to eq(:label)
      expect(chips.map { marker[node[text: 'Materiał Partnera', class_names: [_1]]] }).to all(eq(:paid_label))
      expect(marker[node[text: 'Sponsored'], [block, node[class_names: %w[category], text: '']]]).to eq(:paid_label)
    end

    it 'reads labels inside an anchor, but never inside a heading', :aggregate_failures do
      expect(marker[node[text: 'Werbung'], [block, node[name: :a, text: ''], node[name: :span, text: '']]])
        .to eq(:label)
      expect(marker[node[text: 'Werbung'], [node[name: :h3, text: ''], block]]).to be_nil
      expect(marker[node[text: 'Sponsored'], [node[name: :h3, text: ''], block]]).to be_nil
    end

    it 'ignores labels inside running text or an inline chip', :aggregate_failures do
      expect(marker[node[name: :strong, text: 'Werbung:'], [node[name: :p, text: ' Wer Produkte zeigt.']]]).to be_nil
      expect(marker[node[name: :b, text: 'Werbung'], [node[name: :p, text: 'Die  kehrt zurück.']]]).to be_nil
      expect(marker[node[text: 'Werbung'], [block, node[name: :em, text: 'Die ']]]).to be_nil
      expect(marker[node[text: 'Werbung'], [block, node[class_names: %w[category], text: '']]]).to be_nil
    end

    it 'keeps a standalone label below separators, inline wrappers, and block classes', :aggregate_failures do
      expect(marker[node[text: 'Anzeige'], [node[name: :div, text: ' | '], node[name: :span, text: '']]]).to eq(:label)
      expect(marker[node[text: 'Anzeige'], [node[name: :div, text: 'Mehr'], block]]).to eq(:label)
      expect(marker[node[text: 'Anzeige'], [node[name: :article, text: '', class_names: %w[category-news]]]])
        .to eq(:label)
    end

    it 'is nil for an unmarked node' do
      expect(marker[node[text: '']]).to be_nil
    end
  end

  describe '.paid_text?' do
    it 'is true only for a whole paid phrase', :aggregate_failures do
      expect(['Materiał Partnera', ' Sponsored ', '提供：アクメ'].map { described_class.paid_text?(_1) }).to all(be(true))
      rejected = ['Werbung', 'Anzeige', 'PR', 'Partners', 'Sponsored posts win', '', nil]
      expect(rejected.map { described_class.paid_text?(_1) }).to all(be(false))
    end
  end
end
