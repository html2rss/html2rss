# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Html2rss::Scoring::Observation do
  let(:blank_attributes) do
    {
      title_word_count: 0, path_length: 0, content_path: false, publish_marker: false,
      descriptive_context: false, article_container: false, content_tokens: false, junk_tokens: false,
      utility_prefix_title: false, recommended_title: false, utility_path: false, strong_post_suffix: false,
      shallow: false, high_confidence_junk_path: false, high_confidence_utility_destination: false,
      selected_anchor_present: false
    }
  end
  let(:build) { ->(**overrides) { described_class.new(**blank_attributes, **overrides) } }
  let(:positive_signals) { %i[article_container publish_marker descriptive_context content_path] }
  let(:strong_signals) { positive_signals.to_h { |signal| [signal, true] } }
  let(:chrome_title) do
    { selected_anchor_present: true, recommended_title: true, shallow: true }
  end
  let(:utility_chrome_title) do
    { selected_anchor_present: true, utility_prefix_title: true, high_confidence_utility_destination: true }
  end

  describe '#weak_signals?' do
    it 'is weak when no positive content signal is present' do
      expect(build.call).to be_weak_signals
    end

    it 'is weak when exactly one positive content signal is present', :aggregate_failures do
      positive_signals.each do |signal|
        expect(build.call(signal => true)).to be_weak_signals
      end
    end

    it 'is not weak when two positive content signals are present', :aggregate_failures do
      positive_signals.combination(2).each do |pair|
        expect(build.call(**pair.to_h { |signal| [signal, true] })).not_to be_weak_signals
      end
    end

    it 'ignores non-positive signals when counting' do
      expect(build.call(shallow: true, junk_tokens: true, high_confidence_junk_path: true)).to be_weak_signals
    end
  end

  describe '#hard_junk?' do
    it 'drops high-confidence junk paths in strict mode regardless of content signals' do
      expect(build.call(high_confidence_junk_path: true, **strong_signals)).to be_hard_junk
    end

    it 'defaults to strict mode' do
      expect(build.call(high_confidence_junk_path: true, **strong_signals).hard_junk?).to be(true)
    end

    it 'keeps high-confidence junk paths with strong content signals in lenient mode' do
      expect(build.call(high_confidence_junk_path: true, **strong_signals).hard_junk?(mode: :lenient)).to be(false)
    end

    it 'drops high-confidence junk paths with weak signals in lenient mode' do
      expect(build.call(high_confidence_junk_path: true).hard_junk?(mode: :lenient)).to be(true)
    end

    it 'keeps observations without junk or chrome signals in both modes', :aggregate_failures do
      observation = build.call(**strong_signals)

      expect(observation.hard_junk?).to be(false)
      expect(observation.hard_junk?(mode: :lenient)).to be(false)
    end

    it 'keeps weak observations without junk paths in lenient mode' do
      expect(build.call.hard_junk?(mode: :lenient)).to be(false)
    end

    it 'raises for an unknown mode' do
      expect { build.call.hard_junk?(mode: :bogus) }
        .to raise_error(ArgumentError, 'unknown hard_junk mode: :bogus')
    end

    it 'drops recommended chrome titles that are shallow and weak in both modes', :aggregate_failures do
      observation = build.call(**chrome_title)

      expect(observation.hard_junk?).to be(true)
      expect(observation.hard_junk?(mode: :lenient)).to be(true)
    end

    it 'keeps recommended chrome titles when any chrome condition is missing', :aggregate_failures do
      chrome_title.each_key do |missing|
        observation = build.call(**chrome_title, missing => false)

        expect(observation.hard_junk?).to be(false)
      end
    end

    it 'keeps recommended chrome titles when a content signal makes them non-weak' do
      expect(build.call(**chrome_title, **strong_signals).hard_junk?).to be(false)
    end

    it 'drops utility-prefixed chrome titles pointing at utility destinations', :aggregate_failures do
      observation = build.call(**utility_chrome_title)

      expect(observation.hard_junk?).to be(true)
      expect(observation.hard_junk?(mode: :lenient)).to be(true)
    end

    it 'keeps utility-prefixed chrome titles when any utility condition is missing', :aggregate_failures do
      utility_chrome_title.each_key do |missing|
        observation = build.call(**utility_chrome_title, missing => false)

        expect(observation.hard_junk?).to be(false)
      end
    end

    it 'keeps utility-prefixed chrome titles when a content signal makes them non-weak' do
      expect(build.call(**utility_chrome_title, **strong_signals).hard_junk?).to be(false)
    end

    it 'keeps utility-prefixed chrome titles without an anchor' do
      observation = build.call(**utility_chrome_title, selected_anchor_present: false)

      expect(observation.hard_junk?).to be(false)
    end
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers
