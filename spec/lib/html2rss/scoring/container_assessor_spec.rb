# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe Html2rss::Scoring::ContainerAssessor do
  subject(:assessor) { described_class.new }

  let(:resolver) { Html2rss::Scoring::LinkResolver.new('https://example.com/') }
  let(:news_href) { '/news/2024/platform-launch-notes' }
  let(:news_facts) { resolver.destination_facts(news_href) }
  let(:body_text) { 'Engineers shipped the platform launch notes for every team in the company this spring.' }
  let(:heading) { build_node(name: :h2, text: 'Platform launch notes for teams') }
  let(:anchor) { build_node(name: :a, href: news_href, text: 'Read the story') }
  let(:article) do
    Html2rss::SST::Node.build(
      name: :article,
      attrs: Html2rss::SST::Attrs.build(class_names: %w[article-card]),
      children: [heading, Html2rss::SST::Node.build(name: :time, own_text: 'May 1, 2024'),
                 build_node(name: :p, text: body_text)]
    )
  end

  describe '#call' do
    it 'uses injected token regexps instead of LinkResolver defaults', :aggregate_failures do
      assessor = described_class.new(content_token_regexp: /custom-content/, junk_token_regexp: /custom-junk/)
      content = assessor.call(build_node(class_names: %w[custom-content]), nil, destination_facts: nil)
      junk = assessor.call(build_node(class_names: %w[custom-junk]), nil, destination_facts: nil)

      expect(content).to have_attributes(content_tokens: true, junk_tokens: false)
      expect(junk).to have_attributes(content_tokens: false, junk_tokens: true)
    end

    it 'assesses a rich article container against its destination facts', :aggregate_failures do
      expect(assessor.call(article, anchor, destination_facts: news_facts)).to have_attributes(
        title_word_count: 5, path_length: news_href.length, content_path: true, publish_marker: true,
        descriptive_context: true, article_container: true, content_tokens: true, junk_tokens: false,
        utility_prefix_title: false, recommended_title: false, utility_path: false, strong_post_suffix: true,
        shallow: false, high_confidence_junk_path: false, high_confidence_utility_destination: false,
        selected_anchor_present: true
      )
    end

    it 'derives a sparse junk container from its anchor and reports absent facts as nil', :aggregate_failures do
      root = build_node(name: :div, class_names: %w[sidebar])
      subscribe = build_node(name: :a, href: '/subscribe', text: 'Subscribe to newsletter')

      expect(assessor.call(root, subscribe, destination_facts: nil)).to have_attributes(
        title_word_count: 3, path_length: 0, content_path: nil, publish_marker: false, descriptive_context: false,
        article_container: false, content_tokens: false, junk_tokens: true, utility_prefix_title: true,
        recommended_title: false, utility_path: nil, strong_post_suffix: nil, shallow: nil,
        high_confidence_junk_path: nil, high_confidence_utility_destination: nil, selected_anchor_present: true
      )
    end

    it 'reports no selected anchor and an empty title when the container has no heading or anchor',
       :aggregate_failures do
      expect(assessor.call(build_node(name: :div), nil, destination_facts: nil)).to have_attributes(
        title_word_count: 0, selected_anchor_present: false, article_container: false
      )
    end

    it 'flags recommended anchor text as a recommended title' do
      recommended = build_node(name: :a, href: '/more', text: 'Empfohlen für dich')

      expect(assessor.call(build_node(name: :div), recommended, destination_facts: nil).recommended_title).to be(true)
    end

    it 'classifies tokens from the container id as well as its class names', :aggregate_failures do
      sidebar = Html2rss::SST::Node.build(name: :div, attrs: Html2rss::SST::Attrs.build(id: 'sidebar'))
      article_id = Html2rss::SST::Node.build(name: :div, attrs: Html2rss::SST::Attrs.build(id: 'article'))

      expect(assessor.call(sidebar, nil, destination_facts: nil).junk_tokens).to be(true)
      expect(assessor.call(article_id, nil, destination_facts: nil).content_tokens).to be(true)
    end

    it 'does not count the entry title as descriptive context' do
      root = build_node(name: :article, children: [build_node(name: :h2, text: 'Platform launch notes for teams'),
                                                   build_node(name: :p, text: 'Short body here')])

      expect(assessor.call(root, nil, destination_facts: nil).descriptive_context).to be(false)
    end

    it 'counts destination path length from the facts URL' do
      shallow = resolver.destination_facts('/a')

      expect(assessor.call(article, anchor, destination_facts: shallow).path_length).to eq(2)
    end
  end

  describe '#entry_title' do
    it 'prefers the heading over the selected anchor for the title' do
      expect(assessor.call(article, anchor, destination_facts: nil).title_word_count).to eq(5)
    end

    it 'falls back to the selected anchor text when there is no heading' do
      root = build_node(name: :div, children: [build_node(name: :p, text: 'Only paragraph text')])

      expect(assessor.call(root, anchor, destination_facts: nil).title_word_count).to eq(3)
    end

    it 'uses an empty title when neither a heading nor an anchor is present', :aggregate_failures do
      root = build_node(name: :div, children: [build_node(name: :p, text: 'Only paragraph text')])

      expect(assessor.call(root, nil, destination_facts: nil).title_word_count).to eq(0)
      expect(assessor.call(build_node(name: :div), nil, destination_facts: nil).title_word_count).to eq(0)
    end
  end

  describe '#publish_marker?' do
    it 'treats a time element anywhere in the container as a publish marker' do
      root = build_node(name: :div, children: [build_node(name: :span, children: [build_node(name: :time)])])

      expect(assessor.call(root, nil, destination_facts: nil).publish_marker).to be(true)
    end

    it 'treats a datetime attribute as a publish marker' do
      root = Html2rss::SST::Node.build(name: :div, attrs: Html2rss::SST::Attrs.build(datetime: '2024-05-01'))

      expect(assessor.call(root, nil, destination_facts: nil).publish_marker).to be(true)
    end

    it 'treats datePublished and dateModified itemprops as publish markers', :aggregate_failures do
      %w[datePublished dateModified].each do |itemprop|
        root = Html2rss::SST::Node.build(name: :div, attrs: Html2rss::SST::Attrs.build(itemprop:))

        expect(assessor.call(root, nil, destination_facts: nil).publish_marker).to be(true)
      end
    end

    it 'ignores other itemprops' do
      root = Html2rss::SST::Node.build(name: :div, attrs: Html2rss::SST::Attrs.build(itemprop: 'author'))

      expect(assessor.call(root, nil, destination_facts: nil).publish_marker).to be(false)
    end
  end

  describe '#descriptive_context?' do
    it 'requires more than 30 characters of context', :aggregate_failures do
      exactly_thirty = build_node(name: :p, text: 'abc abc abc abc abc abc abc ab')
      just_over = build_node(name: :p, text: 'abc abc abc abc abc abc abc abcd')

      expect(assessor.call(exactly_thirty, nil, destination_facts: nil).descriptive_context).to be(false)
      expect(assessor.call(just_over, nil, destination_facts: nil).descriptive_context).to be(true)
    end

    it 'strips the entry title before measuring context', :aggregate_failures do
      root = build_node(name: :article, children: [build_node(name: :h2, text: 'Platform launch notes for teams'),
                                                   build_node(name: :p, text: 'Short body here')])

      expect(assessor.call(root, nil, destination_facts: nil).descriptive_context).to be(false)
      expect(assessor.call(build_node(name: :div), nil, destination_facts: nil).descriptive_context).to be(false)
    end

    it 'matches titles containing regexp metacharacters literally' do
      root = build_node(name: :article, children: [build_node(name: :h2, text: 'Launch (beta) notes for teams'),
                                                   build_node(name: :p, text: 'Short body here')])

      expect(assessor.call(root, nil, destination_facts: nil).descriptive_context).to be(false)
    end

    it 'requires at least eight words of context' do
      seven_long_words = build_node(name: :p, text: Array.new(7, 'abcdefgh').join(' '))

      expect(assessor.call(seven_long_words, nil, destination_facts: nil).descriptive_context).to be(false)
    end
  end

  describe '#word_count' do
    it 'counts alphanumeric words and ignores punctuation' do
      heading_with_punctuation = build_node(name: :h2, text: 'Platform-launch, notes!')

      expect(assessor.call(heading_with_punctuation, nil, destination_facts: nil).title_word_count).to eq(3)
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
