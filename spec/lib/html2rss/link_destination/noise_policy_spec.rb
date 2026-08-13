# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::LinkDestination::NoisePolicy do
  subject(:policy) { described_class.new(link_resolver:, index: document.index) }

  let(:base_url) { 'https://example.com/articles/' }
  let(:link_resolver) { Html2rss::Scoring::LinkResolver.new(base_url) }
  let(:html) do
    '<html><body><article><a href="/news/2024/platform-launch-notes">Platform launch notes</a></article></body></html>'
  end
  let(:document) { Html2rss::SST::Normalizer.call(Nokogiri::HTML(html)) }

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
      doc = Html2rss::SST::Normalizer.call(
        Nokogiri::HTML(<<~HTML)
          <html><body><article><a href="/news/2024/platform-launch-notes"><img src="/i.png"></a></article></body></html>
        HTML
      )
      anchor = doc.root.find(&:link?)
      facts = link_resolver.destination_facts(anchor)
      policy = described_class.new(link_resolver:, index: doc.index)

      expect(policy.noise_anchor?(text: '', destination_facts: facts, anchor:)).to be(true)
    end

    it 'rejects anchors nested under utility landmarks outside the content container' do # rubocop:disable RSpec/ExampleLength
      doc = Html2rss::SST::Normalizer.call(Nokogiri::HTML(<<~HTML))
        <html><body>
          <article>
            <nav><a href="/news/2024/platform-launch-notes">Related</a></nav>
            <h2><a href="/news/2024/other-story">Other story</a></h2>
          </article>
        </body></html>
      HTML
      container = doc.root.find { |n| n.name == :article }
      landmark_anchor = container.find { |n| n.link? && n.visible_text.to_s == 'Related' }
      facts = link_resolver.destination_facts(landmark_anchor)
      policy = described_class.new(link_resolver:, index: doc.index)

      expect(
        policy.noise_anchor?(
          text: 'Related',
          destination_facts: facts,
          anchor: landmark_anchor,
          container:
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
  end
end
