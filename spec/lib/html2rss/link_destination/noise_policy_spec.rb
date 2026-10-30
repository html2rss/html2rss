# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::NoisePolicy do
  subject(:policy) { described_class.new(link_resolver:) }

  let(:base_url) { 'https://example.com/articles/' }
  let(:link_resolver) { Html2rss::Scoring::LinkResolver.new(base_url) }
  let(:anchor_for) { ->(html) { Html2rss::SST::Normalizer.call(html).root.find(&:link?) } }

  describe '#noise_anchor?' do
    it 'rejects taxonomy destinations', :aggregate_failures do
      facts = link_resolver.destination_facts('/category/security')
      expect(policy.noise_anchor?(text: 'Security', destination_facts: facts)).to be(true)
    end

    it 'keeps content permalinks eligible' do
      facts = link_resolver.destination_facts('/news/2024/platform-launch-notes')
      expect(policy.noise_anchor?(text: 'Platform launch notes', destination_facts: facts)).to be(false)
    end

    it 'rejects utility-prefix labels on high-confidence utility destinations' do
      facts = link_resolver.destination_facts('/login')
      expect(policy.noise_anchor?(text: 'Login to continue', destination_facts: facts)).to be(true)
    end

    it 'rejects icon-only anchors' do # rubocop:disable RSpec/ExampleLength
      doc = Html2rss::SST::Normalizer.call(<<~HTML)
        <html><body><article><a href="/news/2024/platform-launch-notes"><img src="/i.png"></a></article></body></html>
      HTML
      anchor = doc.root.find(&:link?)
      facts = link_resolver.destination_facts(anchor)

      expect(policy.noise_anchor?(text: '', destination_facts: facts, anchor:)).to be(true)
    end

    it 'rejects when caller reports a utility landmark ancestor' do # rubocop:disable RSpec/ExampleLength
      facts = link_resolver.destination_facts('/news/2024/platform-launch-notes')

      expect(
        policy.noise_anchor?(
          text: 'Related',
          destination_facts: facts,
          utility_landmark_ancestor: true
        )
      ).to be(true)
    end

    it 'suppresses utility chrome text on weak destinations off the heading' do
      facts = link_resolver.destination_facts('/widget-xyz-detail')
      expect(policy.noise_anchor?(text: 'Contact', destination_facts: facts, heading_anchor: false)).to be(true)
    end

    it 'keeps heading-linked utility labels when the destination is not high-confidence utility' do
      facts = link_resolver.destination_facts('/widget-xyz-detail')
      expect(policy.noise_anchor?(text: 'Contact', destination_facts: facts, heading_anchor: true)).to be(false)
    end

    context 'without destination facts' do
      it 'treats the anchor as noise' do
        expect(policy.noise_anchor?(text: 'Read more', destination_facts: nil)).to be(true)
      end
    end

    # Each row isolates one eligibility clause: [label, href, text, options, expected].
    {
      'short utility label at three words' => ['/about', 'About us here', { heading_anchor: true }, true],
      'short utility label at four words' => ['/about', 'About us here now', { heading_anchor: true }, false],
      'short utility label with blank text' => ['/about', '', { heading_anchor: true }, true],
      'short utility label excluded on content routes' => ['/news/about', 'About', { heading_anchor: true }, false],
      'short utility label excluded by strong post suffix' =>
        ['/misc/dating/press/big-news-story-here', 'Dating', { heading_anchor: true }, false],
      'recommended chrome on a shallow content route' => ['/news', 'Recommended for you', {}, true],
      'recommended chrome suppressed on a heading' => ['/news', 'Recommended for you', { heading_anchor: true }, false],
      'recommended chrome requires a shallow route' =>
        ['/news/2024/platform-launch-notes', 'Recommended for you', {}, false],
      'utility prefix with several words on a high-confidence destination' =>
        ['/login', 'Subscribe to our weekly newsletter today', { heading_anchor: true }, true],
      'utility prefix on a weak destination is kept' =>
        ['/widget-xyz-detail', 'Subscribe to our newsletter', { heading_anchor: true }, false],
      'utility label on a vanity destination' =>
        ['/signup', 'Sign up for our weekly updates now', { heading_anchor: true }, true],
      'non-utility text on a vanity destination is kept' =>
        ['/signup', 'Read our weekly updates now', { heading_anchor: true }, false],
      'utility label on a weak destination is kept' =>
        ['/widget-xyz-detail', 'Sign up for our weekly updates now', { heading_anchor: true }, false],
      'taxonomy destinations are noise for any text' =>
        ['/category/security', 'Latest security research roundup', {}, true],
      'short utility label with nil text' => ['/about', nil, { heading_anchor: true }, true],
      'utility chrome text is kept on shallow content routes' => ['/news', 'Share', {}, false],
      'utility chrome text is kept on content routes' => ['/news/2024/platform-launch-notes', 'Share', {}, false],
      'utility chrome text is kept under a strong post suffix' =>
        ['/misc/press/big-news-story-here', 'Share', {}, false],
      'utility chrome text suppressed on weak routes off the heading' => ['/widget-xyz-detail', 'Share', {}, true],
      'non-utility text on a weak route is kept' => ['/widget-xyz-detail', 'Read the report', {}, false]
    }.each do |label, (href, text, options, expected)|
      it "classifies #{label}" do
        facts = link_resolver.destination_facts(href)
        expect(policy.noise_anchor?(text:, destination_facts: facts, **options)).to be(expected)
      end
    end

    context 'with icon-only anchors' do
      let(:facts) { link_resolver.destination_facts('/news/2024/platform-launch-notes') }

      it 'rejects an image anchor with symbol-only text' do
        anchor = anchor_for.call('<html><body><a href="/x"><img src="/i.png"></a></body></html>')
        expect(policy.noise_anchor?(text: '→', destination_facts: facts, anchor:)).to be(true)
      end

      it 'rejects an image anchor with nil text' do
        anchor = anchor_for.call('<html><body><a href="/x"><img src="/i.png"></a></body></html>')
        expect(policy.noise_anchor?(text: nil, destination_facts: facts, anchor:)).to be(true)
      end

      it 'keeps an icon anchor that carries a word' do
        anchor = anchor_for.call('<html><body><a href="/x"><img src="/i.png"></a></body></html>')
        expect(policy.noise_anchor?(text: 'Read', destination_facts: facts, anchor:)).to be(false)
      end

      it 'keeps an anchor without icon children' do
        anchor = anchor_for.call('<html><body><a href="/x"><span></span></a></body></html>')
        expect(policy.noise_anchor?(text: '', destination_facts: facts, anchor:)).to be(false)
      end

      it 'keeps an empty-text anchor when no anchor node is given' do
        expect(policy.noise_anchor?(text: '', destination_facts: facts, anchor: nil)).to be(false)
      end
    end
  end
end
