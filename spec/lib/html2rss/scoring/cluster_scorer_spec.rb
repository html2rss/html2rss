# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength
RSpec.describe Html2rss::Scoring::ClusterScorer do
  subject(:scorer) { described_class.new }

  let(:words_node) { ->(count) { build_node(name: :p, text: Array.new(count, 'word').join(' ')) } }

  describe '#select_best_group' do
    it 'returns an empty array when there are no groups' do
      expect(scorer.select_best_group({})).to eq([])
    end

    it 'returns the nodes of the only eligible group' do
      nodes = [words_node.call(5)]

      expect(scorer.select_best_group('only' => nodes)).to be(nodes)
    end

    it 'returns an empty array when no group reaches MIN_AVG_WORDS' do
      expect(scorer.select_best_group('short' => [words_node.call(4)])).to eq([])
    end

    it 'treats a group averaging exactly MIN_AVG_WORDS as eligible' do
      nodes = [words_node.call(4), words_node.call(6)]

      expect(scorer.select_best_group('edge' => nodes)).to be(nodes)
    end

    it 'ignores groups without nodes' do
      nodes = [words_node.call(5)]

      expect(scorer.select_best_group('empty' => [], 'real' => nodes)).to be(nodes)
    end

    it 'returns an empty array when the only group is empty' do
      expect(scorer.select_best_group('empty' => [])).to eq([])
    end

    it 'prefers the group with more nodes when word density is equal' do
      larger = [words_node.call(5), words_node.call(5)]
      smaller = [words_node.call(5)]

      expect(scorer.select_best_group('smaller' => smaller, 'larger' => larger)).to be(larger)
    end

    it 'prefers the group with denser text when node counts are equal' do
      dense = [words_node.call(20)]
      sparse = [words_node.call(5)]

      expect(scorer.select_best_group('sparse' => sparse, 'dense' => dense)).to be(dense)
    end

    it 'weighs average words at one fifth against node count' do
      many = [words_node.call(5), words_node.call(5), words_node.call(5), words_node.call(5)]
      wide = [words_node.call(20)]

      expect(scorer.select_best_group('many' => many, 'wide' => wide)).to be(many)
    end

    it 'keeps the earlier group when scores tie' do
      first = [words_node.call(5)]
      second = [words_node.call(5)]

      expect(scorer.select_best_group('first' => first, 'second' => second)).to be(first)
    end

    it 'awards HEADING_BONUS to groups with a heading element' do
      heading = [build_node(name: :article, children: [build_node(name: :h2, text: 'Title words here for test')])]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'heading' => heading)).to be(heading)
    end

    it 'does not award HEADING_BONUS when the heading bonus is outweighed by size' do
      heading = [build_node(name: :h2, text: 'Title words here plus more')]
      plain = Array.new(25) { words_node.call(5) }

      expect(scorer.select_best_group('heading' => heading, 'plain' => plain)).to be(plain)
    end

    it 'awards HEADING_BONUS when only one node in the group is a heading' do
      mixed = [build_node(name: :h2, text: 'one two three four five'), words_node.call(5)]
      plain = Array.new(21) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'mixed' => mixed)).to be(mixed)
    end

    it 'awards HEADING_BONUS to bold title classes', :aggregate_failures do
      %w[font-bold font-semibold].each do |class_name|
        bold = [build_node(name: :span, class_names: [class_name], text: 'one two three four five')]
        plain = Array.new(20) { words_node.call(5) }

        expect(scorer.select_best_group('plain' => plain, 'bold' => bold)).to be(bold)
      end
    end

    it 'does not treat other font classes as heading markers' do
      light = [build_node(name: :span, class_names: %w[font-light], text: 'one two three four five')]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('light' => light, 'plain' => plain)).to be(plain)
    end

    it 'awards TIME_BONUS to groups with a time element' do
      timed = [build_node(name: :div, children: [build_node(name: :time, text: 'one two three four five')])]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'timed' => timed)).to be(timed)
    end

    it 'awards TIME_BONUS when only one node in the group is timed' do
      timed = build_node(name: :time, text: 'one two three four five')
      mixed = [build_node(name: :div, children: [timed]), words_node.call(5)]
      plain = Array.new(21) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'mixed' => mixed)).to be(mixed)
    end

    it 'awards TIME_BONUS to groups with a datetime attribute' do
      attrs = Html2rss::SST::Attrs.build(datetime: '2024-05-01T10:00')
      timed = [Html2rss::SST::Node.build(name: :div, attrs:, own_text: 'one two three four five')]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'timed' => timed)).to be(timed)
    end

    it 'awards DATE_BONUS to groups with ISO-like dates in visible text' do
      dated = [build_node(name: :p, text: 'Posted 2024-05-01 by staff')]
      plain = Array.new(40) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'dated' => dated)).to be(dated)
    end

    it 'awards DATE_BONUS when only one node in the group is dated' do
      mixed = [build_node(name: :p, text: 'Posted 2024-05-01 by staff'), words_node.call(5)]
      plain = Array.new(41) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'mixed' => mixed)).to be(mixed)
    end

    it 'looks for dates in visible text only, not in class names' do
      classed = [build_node(name: :p, class_names: %w[2024-05-01], text: 'one two three four five')]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('classed' => classed, 'plain' => plain)).to be(plain)
    end

    it 'skips nodes without visible text when looking for dates' do
      blank = build_node(name: :div)
      dated = build_node(name: :p, text: 'Posted 2024-05-01 by staff team one two three four')
      plain = Array.new(21) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'blank_dated' => [blank, dated])).to eq([blank, dated])
    end

    it 'awards DATE_BONUS to groups with slash-separated dates' do
      dated = [build_node(name: :p, text: 'Posted 2024/05/01 by staff')]
      plain = Array.new(40) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'dated' => dated)).to be(dated)
    end

    it 'awards DATE_BONUS to groups with month names as whole words' do
      dated = [build_node(name: :p, text: 'Posted in Jan by staff')]
      plain = Array.new(40) { words_node.call(5) }

      expect(scorer.select_best_group('plain' => plain, 'dated' => dated)).to be(dated)
    end

    it 'recognizes every abbreviated month name as a date marker', :aggregate_failures do
      plain = Array.new(20) { words_node.call(5) }
      %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].each do |month|
        [month, month.downcase].each do |spelling|
          dated = [build_node(name: :p, text: "Posted #{spelling} one two three four")]

          expect(scorer.select_best_group('plain' => plain, 'dated' => dated)).to be(dated)
        end
      end
    end

    it 'does not treat month prefixes inside words as dates' do
      janitor = [build_node(name: :p, text: 'Janitor staff team now')]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('janitor' => janitor, 'plain' => plain)).to be(plain)
    end

    it 'only counts a group as dated when some node carries a date' do
      undated = [build_node(name: :p, text: 'one two three four five')]
      plain = Array.new(20) { words_node.call(5) }

      expect(scorer.select_best_group('undated' => undated, 'plain' => plain)).to be(plain)
    end
  end

  describe '#avg_words' do
    it 'averages the word counts of the nodes' do
      expect(scorer.avg_words([words_node.call(2), words_node.call(4)])).to eq(3.0)
    end

    it 'returns a float' do
      expect(scorer.avg_words([words_node.call(3)])).to be_a(Float)
    end

    it 'memoizes word counts per node', :aggregate_failures do
      node = instance_double(Html2rss::SST::Node, word_count: 7)

      expect(scorer.avg_words([node])).to eq(7.0)
      expect(scorer.avg_words([node])).to eq(7.0)
      expect(node).to have_received(:word_count).once
    end
  end
end

# rubocop:enable RSpec/ExampleLength
