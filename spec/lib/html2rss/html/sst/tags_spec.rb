# frozen_string_literal: true

RSpec.describe Html2rss::Html::SST::Tags do
  describe 'chrome scope rule (Html::SST::Tags.chrome_scope)' do
    {
      %w[<div> page] => :page,
      %w[<header> page] => :chrome,
      %w[<footer> page] => :chrome,
      %w[<nav> page] => :chrome,
      %w[<dialog> sectioned] => :chrome,
      %w[<nav> sectioned] => :peripheral,
      %w[<footer> sectioned] => :peripheral,
      %w[<aside> page] => :peripheral,
      %w[<menu> page] => :peripheral,
      ['<div role="complementary">', 'page'] => :peripheral,
      %w[<header> peripheral] => :peripheral,
      %w[<article> peripheral] => :peripheral,
      ['<div role="banner">', 'peripheral'] => :peripheral,
      ['<div role="navigation">', 'peripheral'] => :chrome,
      %w[<header> sectioned] => :sectioned,
      %w[<section> page] => :sectioned,
      ['<div role="main">', 'page'] => :sectioned,
      ['<div role="MAIN">', 'page'] => :sectioned,
      ['<div role="mainly">', 'page'] => :page,
      %w[<article> chrome] => :chrome,
      %w[<div> sectioned] => :sectioned,
      %w[<svg> sectioned] => :chrome
    }.each do |(markup, scope), expected|
      it "maps #{markup} under #{scope} to #{expected}" do
        element = Nokogiri::HTML::DocumentFragment.parse(markup).child

        expect(described_class.chrome_scope(element, scope.to_sym, all_scope)).to eq(expected)
      end
    end

    it 'reads the tag it is handed instead of re-deriving it from the element', :aggregate_failures do
      element = Nokogiri::HTML::DocumentFragment.parse('<div></div>').child

      expect(described_class.chrome_scope(element, :page, all_scope, 'header')).to eq(:chrome)
      expect(described_class.chrome_scope(element, :page, all_scope)).to eq(:page)
    end

    context 'with a page-only language declaring the pager concepts' do
      let(:xx) do
        terms = Html2rss::Vocabulary::CONCEPTS.to_h { [_1, Html2rss::Vocabulary::NONE] }
        terms.merge!(pager_label: %w[bladeren-xx], page_link: %w[volgende-xx], page_link_label: %w[vorige-xx])
        language = Html2rss::Vocabulary::Language.new(code: :xx, terms: terms.freeze)
        Html2rss::Vocabulary.build_scope(:zh, Html2rss::Vocabulary::SHARED_LANGUAGES, own: [language])
      end
      let(:chrome_under) do
        lambda do |markup, scope|
          element = Nokogiri::HTML::DocumentFragment.parse(markup).child
          described_class.chrome_scope(element, :sectioned, scope)
        end
      end

      before do
        own = %i[pager_label page_link page_link_label].to_h { [_1, xx.own_alternation(_1)] }
        by_scope = Html2rss::Html::SST::Tags::PagerReadings::BY_SCOPE
        stub_const('Html2rss::Html::SST::Tags::PagerReadings::BY_SCOPE',
                   by_scope.merge(zh: Html2rss::Html::SST::Tags::PagerReadings.build(own)))
      end

      it 'reads an own pager noun as a whole aria-label, on its own page only', :aggregate_failures do
        nav = '<nav aria-label="Bladeren-xx"></nav>'

        expect(chrome_under.call(nav, xx)).to eq(:chrome)
        expect(chrome_under.call(nav, all_scope)).to eq(:peripheral)
        expect(chrome_under.call('<nav aria-label="Bladeren-xx lijst"></nav>', xx)).to eq(:peripheral)
      end

      it 'reads own previous and next words as page links of a labelled list', :aggregate_failures do
        list = '<ul aria-label="pagination"><li><a>Volgende-xx</a></li><li><a>Vorige-xx</a></li></ul>'

        expect(chrome_under.call(list, xx)).to eq(:chrome)
        expect(chrome_under.call(list, all_scope)).to eq(:sectioned)
      end

      it 'leaves every shared scope on the one shared reading', :aggregate_failures do
        readings = Html2rss::Html::SST::Tags::PagerReadings.const_get(:BY_SCOPE)

        %i[en ja de all].each { expect(readings.fetch(_1)).to be(readings.fetch(:en)) }
        expect(readings.fetch(:zh)).not_to be(readings.fetch(:en))
      end
    end

    {
      %w[nav] => true, %w[aside] => true, %w[footer] => true, %w[menu] => true, %w[div navigation] => true,
      %w[div menubar] => true, %w[div alertdialog] => true, %w[div complementary] => true,
      %w[div search] => false, %w[div] => false
    }.each do |(tag, role), expected|
      it "judges #{tag} role=#{role.inspect} as utility landmark: #{expected}" do
        expect(described_class.utility_landmark?(tag, role)).to be(expected)
      end
    end

    {
      %w[header] => true, %w[div Contentinfo] => true, %w[div banner] => true, %w[nav] => false, %w[div main] => false
    }.each do |(tag, role), expected|
      it "judges #{tag} role=#{role.inspect} as page-level chrome: #{expected}" do
        expect(described_class.page_level_chrome?(tag, role)).to be(expected)
      end
    end
  end
end
