# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::Sponsorship do
  let(:node) do
    lambda do |name: :span, text: nil, class_names: nil, raw: nil|
      Html2rss::SST::Node.build(name:, own_text: text, attrs: Html2rss::SST::Attrs.build(class_names:, raw:))
    end
  end

  describe '.marker?' do
    it 'marks a rel containing sponsored in any case and position', :aggregate_failures do
      expect(described_class.marker?(node[name: :a, raw: { 'rel' => 'sponsored' }])).to be(true)
      expect(described_class.marker?(node[name: :a, raw: { 'rel' => 'nofollow Sponsored' }])).to be(true)
      expect(described_class.marker?(node[name: :a, raw: { 'rel' => 'nofollow noopener' }])).to be(false)
      expect(described_class.marker?(node[name: :a, raw: { 'rel' => 'sponsoredx' }])).to be(false)
    end

    it 'marks advertorial attributes unless switched off', :aggregate_failures do
      expect(described_class.marker?(node[raw: { 'data-sponsored' => '' }])).to be(true)
      expect(described_class.marker?(node[raw: { 'data-advertorial' => 'true' }])).to be(true)
      expect(described_class.marker?(node[raw: { 'data-sponsored' => 'FALSE' }])).to be(false)
      expect(described_class.marker?(node[raw: { 'data-advertorial' => '0' }])).to be(false)
      expect(described_class.marker?(node[raw: { 'data-ad-slot' => 'top' }])).to be(false)
    end

    it 'marks advertorial class tokens only when whole', :aggregate_failures do
      expect(described_class.marker?(node[class_names: %w[card advertorial]])).to be(true)
      expect(described_class.marker?(node[class_names: %w[is-sponsored]])).to be(true)
      expect(described_class.marker?(node[class_names: %w[card sponsored-by-line]])).to be(false)
    end

    it 'marks ad-label class tokens on their own, without label text' do
      tokens = %w[ad-label ad-labels ad-labels__item ad-badge ad-marker ad-label--small]
      expect(tokens).to all(satisfy { described_class.marker?(node[class_names: ['teaser__meta', _1]]) })
    end

    it 'ignores ad-slot and look-alike class tokens' do
      rejected = %w[ad-container ad-tag-container adress head shadow badge ad-labeled teaser__ad-labels
                    ad-label__ ad-labelsx Ad-label]
      expect(rejected.select { described_class.marker?(node[class_names: [_1]]) }).to be_empty
    end

    it 'never reads paywall markers as sponsorship' do
      paywall = [{ 'data-paid-category' => 'plus' }, { 'data-testid' => 'paid-teaser' },
                 { 'data-tracking-paid-category' => 'paid' }]
      expect(paywall.select { described_class.marker?(node[raw: _1, class_names: %w[paywall-badge plus-badge]]) })
        .to be_empty
    end

    it 'marks ARIA labels that are exactly an ad label', :aggregate_failures do
      expect(described_class.marker?(node[raw: { 'aria-label' => 'Anzeige' }])).to be(true)
      expect(described_class.marker?(node[raw: { 'aria-roledescription' => 'Advertisement' }])).to be(true)
      expect(described_class.marker?(node[raw: { 'aria-label' => 'Read the story about advertising' }])).to be(false)
    end

    it 'marks element text that is exactly an ad label, but never anchor text', :aggregate_failures do
      expect(described_class.marker?(node[text: ' Werbung '])).to be(true)
      expect(described_class.marker?(node[name: :p, text: '[Sponsored]'])).to be(true)
      expect(described_class.marker?(node[name: :a, text: 'Sponsored'])).to be(false)
      expect(described_class.marker?(node[text: 'Advertising'])).to be(false)
      expect(described_class.marker?(node[])).to be(false)
    end

    it 'marks the closed multilingual label set with surrounding punctuation' do
      labels = ['Anzeige', 'Gesponsert', 'Sponsored content', 'Paid post', 'Advertorial', 'Promoted',
                'Publicité:', 'Contenu sponsorisé', 'Publireportage', 'Publicidad', 'Contenido patrocinado',
                'Publirreportaje', '· Sponsored story ·']
      expect(labels).to all(satisfy { described_class.marker?(node[text: _1]) })
    end

    it 'ignores text that only contains a label' do
      rejected = ['Advertising', 'Sponsored by the harbor trust', 'Anzeigenmarkt', 'Ad']
      expect(rejected.select { described_class.marker?(node[text: _1]) }).to be_empty
    end

    it 'reads rel as whitespace-separated tokens' do
      expect(described_class.marker?(node[name: :a, raw: { 'rel' => "nofollow\tsponsored" }])).to be(true)
    end
  end
end
