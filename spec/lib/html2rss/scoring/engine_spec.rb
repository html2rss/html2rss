# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe Html2rss::Scoring::Engine do
  let(:engine) { described_class.new(link_resolver: Html2rss::Scoring::LinkResolver.new('https://example.com/')) }

  describe '#rank / #rank_top' do
    let(:segments) do
      junk_link = build_node(name: :a, href: '/login', text: 'Login')
      [
        build_segment(root: build_node(name: :div, children: [junk_link]), link: junk_link, position: 0),
        article_segment(href: '/news/deep-story-slug-here', title: 'Deep Story Title Words', position: 1)
      ]
    end

    it 'drops hard-junk destinations and ranks content above chrome', :aggregate_failures do
      ranked = engine.rank(segments)
      expect(ranked.map { _1.primary_link.attrs.href }).to eq(['/news/deep-story-slug-here'])
      expect(ranked.first.final_score).to be > described_class::SCORE_FLOOR
    end

    it 'applies the score floor in rank_top', :aggregate_failures do
      top = engine.rank_top(segments, limit: 10)
      expect(top.size).to eq(1)
      expect(top.first.final_score).to be >= described_class::SCORE_FLOOR
    end

    it 'demotes commerce affiliate paths via utility_path without title word lists' do
      affiliate = article_segment(href: '/dating/singles-in-berlin', title: 'Singles in Berlin finden', position: 0)
      news = article_segment(href: '/news/deep-story-slug-here', title: 'Deep Story Title Words', position: 1)
      expect(engine.rank([affiliate, news]).map { _1.primary_link.attrs.href }).to eq(['/news/deep-story-slug-here'])
    end
  end

  describe '#select_eligible' do
    let(:segments) do
      first_link = build_node(name: :a, href: '/posts/one-two-three', text: 'First Card Title')
      second_link = build_node(name: :a, href: '/posts/four-five-six', text: 'Second Card Title')
      [
        build_segment(root: build_node(name: :li, children: [first_link]), link: first_link, position: 2),
        build_segment(root: build_node(name: :li, children: [second_link]), link: second_link, position: 1)
      ]
    end

    it 'preserves discovery position order after eligibility', :aggregate_failures do
      eligible = engine.select_eligible(segments, limit: 10)
      expect(eligible.map(&:position)).to eq([1, 2])
      expect(eligible.map { _1.primary_link.attrs.href }).to eq(
        ['/posts/four-five-six', '/posts/one-two-three']
      )
    end
  end

  shared_context 'with a stubbed container assessor' do
    let(:blank_observation) do
      {
        title_word_count: 0, path_length: 0, content_path: false, publish_marker: false,
        descriptive_context: false, article_container: false, content_tokens: false, junk_tokens: false,
        utility_prefix_title: false, recommended_title: false, utility_path: false, strong_post_suffix: false,
        shallow: false, high_confidence_junk_path: false, high_confidence_utility_destination: false,
        selected_anchor_present: false
      }
    end
    let(:observation) { ->(**overrides) { Html2rss::Scoring::Observation.new(**blank_observation, **overrides) } }
    let(:assessor) { instance_double(Html2rss::Scoring::ContainerAssessor) }
    let(:strong_signals) { { publish_marker: true, descriptive_context: true } }
    let(:segment) { article_segment(href: '/news/story-one', title: 'Story one', position: 0) }

    before do
      allow(Html2rss::Scoring::ContainerAssessor).to receive(:new).and_return(assessor)
      allow(assessor).to receive(:call).and_return(observation.call)
    end
  end

  describe '#rank' do
    include_context 'with a stubbed container assessor'

    it 'orders by composite score, then discovery position' do
      strong = observation.call(title_word_count: 3, article_container: true)
      weak = observation.call
      segments = [3, 0, 1].map { |position| article_segment(href: '/news/story', title: 'Story', position:) }
      allow(assessor).to receive(:call).and_return(strong, weak, strong)

      expect(engine.rank(segments).map(&:position)).to eq([1, 3, 0])
    end

    it 'computes composite as quality minus junk', :aggregate_failures do
      allow(assessor).to receive(:call)
        .and_return(observation.call(title_word_count: 3, article_container: true, shallow: true))

      expect(engine.rank([segment]).first.score)
        .to have_attributes(composite: 30.0, quality: 50.0, junk: 20.0)
    end

    it 'drops hard junk in strict mode' do
      allow(assessor).to receive(:call).and_return(observation.call(high_confidence_junk_path: true))

      expect(engine.rank([segment])).to eq([])
    end
  end

  describe '#rank_top' do
    include_context 'with a stubbed container assessor'

    it 'keeps segments scoring above the floor' do
      allow(assessor).to receive(:call).and_return(observation.call(title_word_count: 3, article_container: true))

      expect(engine.rank_top([segment]).size).to eq(1)
    end

    it 'keeps segments scoring exactly the floor' do
      allow(assessor).to receive(:call).and_return(observation.call(article_container: true))

      expect(engine.rank_top([segment]).size).to eq(1)
    end

    it 'drops segments below the floor, while rank keeps them', :aggregate_failures do
      expect(engine.rank([segment]).size).to eq(1)
      expect(engine.rank_top([segment])).to eq([])
    end

    it 'caps results at the given limit' do
      allow(assessor).to receive(:call).and_return(observation.call(article_container: true))
      segments = [segment, article_segment(href: '/news/two', title: 'Two', position: 1)]

      expect(engine.rank_top(segments, limit: 1).size).to eq(1)
    end
  end

  describe '#select_eligible with a stubbed container assessor' do
    include_context 'with a stubbed container assessor'

    it 'keeps weak high-confidence junk out but keeps strong content', :aggregate_failures do
      allow(assessor).to receive(:call).and_return(observation.call(high_confidence_junk_path: true))
      expect(engine.select_eligible([segment])).to eq([])

      allow(assessor).to receive(:call)
        .and_return(observation.call(high_confidence_junk_path: true, **strong_signals))
      expect(engine.select_eligible([segment]).size).to eq(1)
    end

    it 'returns results in discovery order and honors the limit', :aggregate_failures do
      segments = [5, 2].map { |position| article_segment(href: '/news/story', title: 'Story', position:) }

      expect(engine.select_eligible(segments).map(&:position)).to eq([2, 5])
      expect(engine.select_eligible(segments, limit: 1).map(&:position)).to eq([2])
    end

    it 'caps results at TOP_K by default' do
      segments = Array.new(described_class::TOP_K + 1) do |position|
        article_segment(href: '/news/story', title: 'Story', position:)
      end

      expect(engine.select_eligible(segments).size).to eq(described_class::TOP_K)
    end
  end

  describe '#initialize' do
    include_context 'with a stubbed container assessor'

    it 'builds the container assessor with the resolver text classifier' do
      resolver = Html2rss::Scoring::LinkResolver.new('https://example.com/')
      described_class.new(link_resolver: resolver)

      expect(Html2rss::Scoring::ContainerAssessor).to have_received(:new)
        .with(text_classifier: resolver.text_classifier)
    end

    it 'uses the injected resolver for destination facts' do
      resolver = instance_double(Html2rss::Scoring::LinkResolver,
                                 text_classifier: Html2rss::LinkDestination::TextClassifier.new, destination_facts: nil)
      described_class.new(link_resolver: resolver).rank([segment])

      expect(resolver).to have_received(:destination_facts).with(segment.primary_link)
    end
  end

  describe '#rank_one' do
    include_context 'with a stubbed container assessor'

    it 'passes the segment root, primary link, and destination facts to the assessor', :aggregate_failures do
      engine.rank([segment])
      facts = Html2rss::Scoring::LinkResolver.new('https://example.com/').destination_facts(segment.primary_link)

      expect(assessor).to have_received(:call)
        .with(segment.root_node, segment.primary_link, destination_facts: facts)
    end

    it 'passes nil destination facts for segments without a primary link', :aggregate_failures do
      resolver = instance_double(Html2rss::Scoring::LinkResolver,
                                 text_classifier: Html2rss::LinkDestination::TextClassifier.new, destination_facts: nil)
      unlinked = build_segment(root: segment.root_node, link: nil)
      described_class.new(link_resolver: resolver).rank([unlinked])

      expect(resolver).not_to have_received(:destination_facts)
      expect(assessor).to have_received(:call).with(segment.root_node, nil, destination_facts: nil)
    end

    it 'builds float composite, quality, and junk scores', :aggregate_failures do
      allow(assessor).to receive(:call)
        .and_return(observation.call(title_word_count: 3, article_container: true, shallow: true))
      score = engine.rank([segment]).first.score

      expect(score).to have_attributes(composite: 30.0, quality: 50.0, junk: 20.0)
      expect([score.composite, score.quality, score.junk]).to all(be_a(Float))
    end

    it 'exposes the quality and junk breakdown as a frozen hash', :aggregate_failures do
      allow(assessor).to receive(:call)
        .and_return(observation.call(title_word_count: 3, article_container: true, shallow: true))
      breakdown = engine.rank([segment]).first.score.breakdown

      expect(breakdown).to eq(title_word_count_ge3: 40, article_container: 10, shallow: 10, weak_container: 10)
      expect(breakdown).to be_frozen
    end

    it 'drops hard junk before scoring' do
      allow(assessor).to receive(:call).and_return(observation.call(high_confidence_junk_path: true))

      expect(engine.rank([segment])).to eq([])
    end

    it 'applies lenient hard-junk rules for select_eligible' do
      allow(assessor).to receive(:call)
        .and_return(observation.call(high_confidence_junk_path: true, **strong_signals))

      expect(engine.select_eligible([segment]).size).to eq(1)
    end
  end

  describe '#apply_rules' do
    include_context 'with a stubbed container assessor'

    let(:breakdown_for) do
      lambda do |**overrides|
        allow(assessor).to receive(:call).and_return(observation.call(**overrides))
        engine.select_eligible([segment]).first.score.breakdown
      end
    end

    it 'scores each quality feature when its predicate holds', :aggregate_failures do
      {
        title_word_count_ge3: [{ title_word_count: 3 }, 40],
        title_word_count_ge7: [{ title_word_count: 7 }, 15],
        path_length_gt6: [{ path_length: 7 }, 20],
        content_path: [{ content_path: true }, 15],
        publish_marker: [{ publish_marker: true }, 15],
        descriptive_context: [{ descriptive_context: true }, 10],
        article_container: [{ article_container: true }, 10],
        content_tokens: [{ content_tokens: true }, 10]
      }.each do |feature, (overrides, weight)|
        expect(breakdown_for.call(**overrides)).to include(feature => weight)
      end
    end

    it 'scores each junk feature when its predicate holds', :aggregate_failures do
      {
        non_content_utility_path: [{ utility_path: true }, 25],
        utility_prefix_title_short: [{ utility_prefix_title: true, title_word_count: 6 }, 15],
        shallow: [{ shallow: true }, 10],
        weak_container: [{}, 10],
        recommended_title_non_content: [{ recommended_title: true }, 10],
        high_confidence_junk_path: [{ high_confidence_junk_path: true, **strong_signals }, 5],
        junk_tokens: [{ junk_tokens: true }, 15]
      }.each do |feature, (overrides, weight)|
        expect(breakdown_for.call(**overrides)).to include(feature => weight)
      end
    end

    it 'does not score quality features at their boundaries' do
      expect(breakdown_for.call(title_word_count: 2, path_length: 6))
        .not_to include(:title_word_count_ge3, :title_word_count_ge7, :path_length_gt6)
    end

    it 'does not score utility paths that are content or post-suffixed', :aggregate_failures do
      expect(breakdown_for.call(utility_path: true, content_path: true))
        .not_to include(:non_content_utility_path)
      expect(breakdown_for.call(utility_path: true, strong_post_suffix: true))
        .not_to include(:non_content_utility_path)
    end

    it 'does not score short utility titles beyond six words' do
      expect(breakdown_for.call(utility_prefix_title: true, title_word_count: 7))
        .not_to include(:utility_prefix_title_short)
    end

    it 'does not score a weak container when publish markers are present' do
      expect(breakdown_for.call(publish_marker: true)).not_to include(:weak_container)
    end

    it 'does not score non-content recommended titles on content paths' do
      expect(breakdown_for.call(recommended_title: true, content_path: true))
        .not_to include(:recommended_title_non_content)
    end

    it 'freezes the feature breakdown' do
      expect(breakdown_for.call(article_container: true)).to be_frozen
    end
  end

  describe '.assert_feature_id!' do
    it 'accepts known feature ids and rejects unknown ones', :aggregate_failures do
      expect(described_class.assert_feature_id!(:content_path)).to eq(:content_path)
      expect { described_class.assert_feature_id!(:bogus) }
        .to raise_error(ArgumentError, 'unknown feature: :bogus')
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
