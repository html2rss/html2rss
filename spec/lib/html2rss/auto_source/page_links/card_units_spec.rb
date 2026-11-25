# frozen_string_literal: true

RSpec.describe 'Html2rss::AutoSource::PageLinks::CardUnits' do
  subject(:units) { units_of.call(body) }

  let(:card) { ->(slug) { %(<article><h2><a href="/news/#{slug}">Story #{slug}</a></h2></article>) } }
  let(:units_of) do
    lambda do |html, skip: nil|
      vocabulary = Html2rss::Vocabulary[:all]
      document = Html2rss::SST::Normalizer.call("<html><body><div>#{html}</div></body></html>", vocabulary:)
      resolver = Html2rss::Scoring::LinkResolver.new('https://example.com/news/')
      claims = Html2rss::AutoSource::PageLinks.const_get(:AnchorClaims).new(resolver, :path.to_proc)
      root = document.root.find { _1.name == :div }
      Html2rss::AutoSource::PageLinks.const_get(:CardUnits).new(root, skip: skip&.call(root), claims:)
    end
  end
  let(:body) { card.call('a') }

  describe '#initialize' do
    it 'freezes the units' do
      expect(units).to be_frozen
    end

    it 'leaves a skipped subtree out of every count', :aggregate_failures do
      skipped = units_of.call(%(#{card.call('a')}<p><a href="/news/b">B</a></p><h2>Skipped</h2>),
                              skip: ->(root) { root.find { _1.name == :p } })
      expect(skipped.cards).to eq(1)
      expect(skipped.stray?).to be(true)
    end
  end

  describe '#cards' do
    {
      'the cards of the root' => [-> { %w[a b c].map { card.call(_1) }.join }, 3],
      'none for a root without destinations' => [-> { '<p>Nothing</p>' }, 0],
      'one for a card without a heading' => [-> { '<section><a href="/news/a">A</a></section>' }, 1],
      'the cards of a crowded child instead of the child' => [
        -> { "<section>#{card.call('a')}#{card.call('b')}</section>" }, 2
      ],
      'the cards beside a crowded child' => [
        -> { "#{card.call('c')}<section>#{card.call('a')}#{card.call('b')}</section>" }, 3
      ],
      'the cards of nested crowded children' => [
        -> { "<section><div>#{card.call('a')}#{card.call('b')}</div>#{card.call('c')}</section>" }, 3
      ],
      'none for a heading without a link' => [-> { '<h2>Title</h2>' }, 0],
      'none for a headline link' => [-> { '<h2><a href="/news/a">A</a></h2>' }, 0],
      'none for a card whose link is no article destination' => [
        -> { '<article><h2><a href="mailto:a@example.com">Mail</a></h2></article>' }, 0
      ],
      'one for a card repeating its destination' => [
        -> { '<article><h2>A</h2><a href="/news/a">A</a><a href="/news/a">More</a></article>' }, 1
      ]
    }.each do |name, (build, count)|
      context "with #{name}" do
        let(:body) { instance_exec(&build) }

        it "counts #{count}" do
          expect(units.cards).to eq(count)
        end
      end
    end
  end

  describe '#card?' do
    {
      'holds one destination and one heading' => [-> { card.call('a') }, true],
      'repeats its one destination' => [
        -> { '<article><h2><a href="/news/a">A</a></h2><a href="/news/a">More</a></article>' }, true
      ],
      'holds an anchor without a destination beside its one destination' => [
        -> { '<article><h2><a href="/news/a">A</a></h2><a href="http://example.com:abc/">Broken</a></article>' }, true
      ],
      'holds two destinations' => [
        -> { '<article><h2>A</h2><a href="/news/a">A</a><a href="/news/b">B</a></article>' }, false
      ],
      'holds two headings' => [-> { '<article><h2>A</h2><h3>B</h3><a href="/news/a">A</a></article>' }, false],
      'holds a heading without a destination' => [-> { '<article><h2>A</h2></article>' }, false],
      'holds a destination without a heading' => [-> { '<article><a href="/news/a">A</a></article>' }, false],
      'holds an anchor that is no article destination' => [
        -> { '<article><h2>A</h2><a href="mailto:a@example.com">Mail</a></article>' }, false
      ]
    }.each do |name, (build, expected)|
      context "with a root that #{name}" do
        let(:body) { instance_exec(&build) }

        it "is #{expected}" do
          expect(units.card?).to be(expected)
        end
      end
    end
  end

  describe '#stray?' do
    {
      'sits outside every card' => [-> { '<h2>Stray</h2>' }, true],
      'is a headline link outside every card' => [-> { '<h2><a href="/news/a">A</a></h2>' }, true],
      'is nested in a plain box beside a card' => [-> { "#{card.call('a')}<section><h2>Stray</h2></section>" }, true],
      'sits in a crowded child' => [
        -> { "<section>#{card.call('a')}#{card.call('b')}<h2>Stray</h2></section>" }, true
      ],
      'precedes a crowded child' => [
        -> { "<h2>Stray</h2><section>#{card.call('a')}#{card.call('b')}</section>" }, true
      ],
      'precedes a text box' => [-> { '<h2>Stray</h2><p>Text</p>' }, true],
      'sits in a card' => [-> { card.call('a') }, false],
      'is absent' => [-> { "#{card.call('a')}<p>Text</p>" }, false],
      'is absent beside a crowded child' => [
        -> { "<section>#{card.call('a')}#{card.call('b')}</section><p>Text</p>" }, false
      ]
    }.each do |name, (build, expected)|
      context "when a heading #{name}" do
        let(:body) { instance_exec(&build) }

        it "is #{expected}" do
          expect(units.stray?).to be(expected)
        end
      end
    end
  end
end
