# frozen_string_literal: true

RSpec.describe Html2rss::SST::Node do
  describe '.build' do
    it 'requires a name' do
      expect { described_class.build(name: nil) }.to raise_error(ArgumentError)
    end

    it 'requires typed attrs' do
      expect { described_class.build(name: :div, attrs: { href: 'x' }) }.to raise_error(ArgumentError)
    end

    it 'exposes predicates, traversal, and leaf checks', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      link = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/post'), own_text: 'Post')
      junk = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '#frag'))
      heading = described_class.build(name: :h2, own_text: 'Title')
      img = described_class.build(name: :img, attrs: Html2rss::SST::Attrs.build(src: '/a.png'))
      nav = described_class.build(name: :nav)
      child_div = described_class.build(name: :div, own_text: 'inner')
      parent_div = described_class.build(name: :div, children: [child_div, link])

      expect(link).to be_link
      expect(junk).not_to be_link
      expect(heading).to be_heading
      expect(img).to be_image
      expect(nav).to be_utility_landmark
      expect(nav).to be_ignored_container_name
      expect(parent_div.word_count).to be >= 1
      expect(parent_div.text_density).to be_a(Float)
      expect(parent_div.descendants).to include(link)
      expect(parent_div.count_descendants).to eq(2)
      expect(parent_div.count_descendants(&:link?)).to eq(1)
      expect(parent_div.find(&:link?)).to eq(link)
    end

    it 'is immutable' do
      node = described_class.build(name: :div, children: [])
      expect { node.children << described_class.build(name: :span) }.to raise_error(FrozenError)
    end

    it 'coerces names to symbols and rejects blank names', :aggregate_failures do
      expect(described_class.build(name: 'div').name).to eq(:div)
      expect { described_class.build(name: '  ') }.to raise_error(ArgumentError, 'name is required')
    end

    it 'defaults missing attrs, children and text to empty values', :aggregate_failures do
      node = described_class.build(name: :span)

      expect(node.attrs).to be(Html2rss::SST::Attrs.empty)
      expect(node.children).to eq([])
      expect(node.own_text).to eq('')
      expect(node.tag_path).to eq('')
    end

    it 'rejects attrs that are not typed and children that are not nodes', :aggregate_failures do
      expect { described_class.build(name: :div, attrs: Object.new) }
        .to raise_error(ArgumentError, 'attrs must be SST::Attrs')
      expect { described_class.build(name: :div, children: ['text']) }
        .to raise_error(ArgumentError, 'children must be SST::Node instances')
    end
  end

  describe 'element predicates' do
    it 'recognises every heading, landmark and ignored container name', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      Html2rss::SST::Tags::HEADING_NAMES.each { |name| expect(described_class.build(name:)).to be_heading }
      Html2rss::SST::Tags::UTILITY_LANDMARK_NAMES.each do |name|
        expect(described_class.build(name:)).to be_utility_landmark
      end
      Html2rss::SST::Tags::IGNORED_CONTAINER_NAMES.each do |name|
        expect(described_class.build(name:)).to be_ignored_container_name
      end
    end

    it 'does not treat other names as headings, landmarks or containers', :aggregate_failures do
      span = described_class.build(name: :span)

      expect(span).not_to be_heading
      expect(span).not_to be_utility_landmark
      expect(span).not_to be_ignored_container_name
      expect(span).not_to be_image
    end

    it 'treats only img elements as images' do
      expect(described_class.build(name: :img)).to be_image
    end
  end

  describe 'links' do
    it 'accepts destinations that are not skipped schemes or fragments', :aggregate_failures do
      expect(described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/post'))).to be_link
      expect(described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: 'https://x.test'))).to be_link
    end

    it 'skips every configured non-content href prefix' do
      Html2rss::SST::Tags::SKIP_HREF_PREFIXES.each do |prefix|
        node = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: "#{prefix}x"))

        expect(node).not_to be_eligible_href
      end
    end

    it 'is not a link without an href or when the element is not an anchor', :aggregate_failures do
      expect(described_class.build(name: :a)).not_to be_link
      expect(described_class.build(name: :span, attrs: Html2rss::SST::Attrs.build(href: '/x'))).not_to be_link
    end
  end

  describe 'traversal and text metrics' do
    let(:document) do
      Html2rss::SST::Normalizer.call(
        '<html><body><div><p>one two</p><a href="/a">a</a><a href="/b">b</a><a href="#x">skip</a></div></body></html>'
      )
    end
    let(:div) { document.root.find { |node| node.name == :div } }

    it 'walks descendants and counts matching ones', :aggregate_failures do
      expect(div.descendants.size).to eq(4)
      expect(div.count_descendants).to eq(div.descendants.size)
      expect(div.count_descendants(&:link?)).to eq(2)
      expect(div.find(&:image?)).to be_nil
    end

    it 'renders visible text with the default, custom and excluded variants', :aggregate_failures do
      expect(div.visible_text).to eq("one two\na b")
      expect(div.visible_text(separator: ' | ')).to eq('one two | a b')
      expect(div.visible_text(exclude: [div.children.first])).to eq('a b')
    end

    it 'counts words and link density from visible text', :aggregate_failures do
      expect(div.word_count).to eq(4)
      expect(div.text_density).to eq(2.0)
    end

    it 'computes the same metrics for nodes built without an index', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      node = described_class.build(
        name: :div,
        children: [described_class.build(name: :p, own_text: 'one'), described_class.build(name: :p, own_text: 'two')]
      )

      expect(node.visible_text).to eq("one\ntwo")
      expect(node.word_count).to eq(2)
      expect(described_class.build(name: :span, own_text: 'one two three').text_density).to eq(3.0)
    end
  end
end
