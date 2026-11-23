# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::Navigator do
  describe 'tag vocabulary' do
    {
      HEADING_TAGS: [:HEADING_NAMES, %w[h1 h2 h3 h4 h5 h6]],
      IGNORED_CONTAINER_TAGS: [:IGNORED_CONTAINER_NAMES, %w[nav footer header dialog svg script style]]
    }.each do |navigator_const, (tags_const, values)|
      it "derives #{navigator_const} from SST::Tags::#{tags_const} with no delta" do
        derived = Html2rss::SST::Tags.const_get(tags_const).to_set(&:to_s)

        expect(described_class.const_get(navigator_const)).to eq(derived).and eq(Set.new(values))
      end
    end

    it 'builds MAIN_ANCHOR_SELECTOR from SST::Tags::SKIP_HREF_PREFIXES' do
      nots = Html2rss::SST::Tags::SKIP_HREF_PREFIXES.map { |prefix| %[:not([href^="#{prefix}"])] }.join

      expect(described_class::MAIN_ANCHOR_SELECTOR).to eq(%(a[href]:not([href=""])#{nots}))
    end
  end

  describe '.usable_card_parent?' do
    let(:document) { Nokogiri::HTML('<body><nav></nav><div class="card"></div></body>') }

    it 'accepts ordinary wrappers and rejects landmarks', :aggregate_failures do
      expect(usable_card?(document.at_css('div'))).to be(true)
      expect(usable_card?(document.at_css('nav'))).to be(false)
      expect(usable_card?(document.at_css('body'))).to be(false)
      expect(usable_card?(document)).to be(false)
    end

    it 'treats uppercase NAV as a card-walk stop' do
      document = Nokogiri::HTML('<html><body><NAV><a href="/home">Home</a></NAV></body></html>')

      expect(usable_card?(document.at_css('NAV'))).to be(false)
    end

    it 'stops at page-level header and footer but not at ones inside sectioning content' do # rubocop:disable RSpec/ExampleLength
      document = Nokogiri::HTML('<body><header id="ph"></header><footer id="pf"></footer>' \
                                '<article><header id="ah"></header><footer id="af"></footer></article>' \
                                '<main><div><header id="mh"></header></div></main>' \
                                '<nav><header id="nh"></header></nav></body>')
      usable = %w[ph pf ah af mh nh].to_h do |id|
        [id, usable_card?(document.at_css("##{id}"))]
      end

      expect(usable).to eq('ph' => false, 'pf' => false, 'ah' => true, 'af' => true, 'mh' => true, 'nh' => false)
    end

    it 'stops at utility landmark roles and page-level banner/contentinfo roles' do # rubocop:disable RSpec/ExampleLength
      html = '<body><div id="rn" role="navigation"></div><div id="rc" role="complementary"></div>' \
             '<div id="rd" role="dialog"></div><dialog id="dl"></dialog><div id="rs" role="search"></div>' \
             '<aside id="as"></aside><div id="pb" role="banner"></div>' \
             '<article><div id="ab" role="banner"></div></article></body>'
      ids = %w[rn rc rd dl rs as pb ab]
      expected = { 'rn' => false, 'rc' => false, 'rd' => false, 'dl' => false, 'rs' => true, 'as' => false,
                   'pb' => false, 'ab' => true }
      sst_root = document_for(html).root
      nokogiri = ids.to_h { |id| [id, usable_card?(Nokogiri::HTML(html).at_css("##{id}"))] }
      sst = ids.to_h do |id|
        [id, usable_card?(sst_root.find { _1.attrs.id == id })]
      end

      expect([nokogiri, sst]).to eq([expected, expected])
    end

    describe 'chrome-scope parity between Nokogiri and SST nodes' do
      let(:html) do
        '<body><header id="page"></header>' \
          '<section><header id="sectioned"></header></section>' \
          '<nav><section><header id="inherited"></header></section></nav>' \
          '<footer><article><footer id="in_footer"></footer></article></footer>' \
          '<div role="navigation"><section><header id="role_nav"></header></section></div>' \
          '<main><nav><header id="main_nav"></header></nav></main></body>'
      end
      let(:ids) { %w[page sectioned inherited in_footer role_nav main_nav] }
      let(:expected) do
        { 'page' => false, 'sectioned' => true, 'inherited' => false, 'in_footer' => false,
          'role_nav' => false, 'main_nav' => true }
      end

      let(:document) { Nokogiri::HTML(html) }
      let(:sst_root) { document_for(html).root }

      it 'agrees on page-level, sectioned and chrome-inherited headers', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        nokogiri = ids.to_h do |id|
          [id, usable_card?(document.at_css("##{id}"))]
        end
        sst = ids.to_h do |id|
          [id, usable_card?(sst_root.find { _1.attrs.id == id })]
        end

        expect(nokogiri).to eq(expected)
        expect(sst).to eq(expected)
      end
    end

    it 'follows the SST chrome index for header and footer nodes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      doc = document_for(
        '<html><body><header>H</header><article><header>A</header></article></body></html>'
      )
      page_header, card_header = doc.root.find_all { _1.name == :header }

      expect(usable_card?(page_header)).to be(false)
      expect(usable_card?(card_header)).to be(true)
      expect(usable_card?(Html2rss::SST::Node.build(name: :header))).to be(false)
    end
  end
end
