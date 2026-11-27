# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleRules::Description do
  let(:vocabulary) { Html2rss::Vocabulary[nil] }

  describe '.date_core' do
    it 'strips a known type-chip suffix after a dash', :aggregate_failures do
      expect(described_class.date_core('12 March 2024 - News article')).to eq('12 March 2024')
      expect(described_class.date_core('12 March 2024 – Press release')).to eq('12 March 2024')
      expect(described_class.date_core('12 March 2024 — News')).to eq('12 March 2024')
    end

    it 'leaves lines without a type-chip suffix unchanged' do
      expect(described_class.date_core('12 March 2024 - something else'))
        .to eq('12 March 2024 - something else')
    end
  end

  describe '.date_shaped?' do
    it 'reads a byline as an author name only when it is name-shaped', :aggregate_failures do
      expect(described_class::Byline.author_of('Von Anna Beispiel')).to eq('Anna Beispiel')
      expect(described_class::Byline.author_of('27 Nov 2026 / by Anna van Beispiel')).to eq('Anna van Beispiel')
      expect(described_class::Byline.author_of('By the end of the year')).to be_nil
      expect(described_class::Byline.author_of('Tram news / by Anna Beispiel')).to be_nil
      expect(described_class::Byline.author_of(nil)).to be_nil
    end

    it 'keeps prose and function-word lines out of bylines', :aggregate_failures do
      ['By Land and Sea', 'By The Associated Press', 'By Order of the King', 'Von Die Zeit',
       'By Anna Maria Beispiel Jones Smith'].each do |line|
        expect(described_class::Byline.author_of(line)).to be_nil
      end
    end

    it 'reads a one-word name, a particle name and two full names', :aggregate_failures do
      expect(described_class::Byline.author_of('By Beispiel')).to eq('Beispiel')
      expect(described_class::Byline.author_of('Von Ursula von der Beispiel')).to eq('Ursula von der Beispiel')
      expect(described_class::Byline.author_of('By Anna Beispiel and Bob Muster')).to eq('Anna Beispiel and Bob Muster')
    end

    it 'collapses and trims whitespace before reading a byline', :aggregate_failures do
      expect(described_class::Byline.author_of("  By Anna Beispiel \n")).to eq('Anna Beispiel')
      expect(described_class::Byline.author_of('By  Anna   Beispiel')).to eq('Anna Beispiel')
      expect(described_class::Byline.author_of("By\u00A0Anna\u00A0\u00A0Beispiel")).to eq('Anna Beispiel')
    end

    it 'reads a byline of exactly the label length but not one character more', :aggregate_failures do
      at_limit = "By A#{'a' * (described_class::MAX_LABEL_CHARS - 4)}"

      expect(at_limit.length).to eq(described_class::MAX_LABEL_CHARS)
      expect(described_class::Byline.author_of(at_limit)).to eq(at_limit.delete_prefix('By '))
      expect(described_class::Byline.author_of("#{at_limit}a")).to be_nil
    end

    it 'does not read a byline that ends like a sentence' do
      expect(described_class::Byline.author_of('By Anna Beispiel.')).to be_nil
    end

    it 'takes the author of the first byline line', :aggregate_failures do
      lines = ['A headline without author', 'By Anna Beispiel', 'By Bert Muster']

      expect(described_class::Byline.first_author(lines)).to eq('Anna Beispiel')
      expect(described_class::Byline.first_author(lines.drop(1))).to eq('Anna Beispiel')
      expect(described_class::Byline.first_author(lines.first(1))).to be_nil
      expect(described_class::Byline.first_author([])).to be_nil
    end

    it 'reads a digitless line without peeling or matching date shapes', :aggregate_failures do
      allow(described_class).to receive(:date_core).and_call_original

      expect(described_class.date_shaped?('Press releases')).to be(false)
      expect(described_class.date_shaped?(nil)).to be(false)
      expect(described_class).not_to have_received(:date_core)
      expect(described_class.date_shaped?('2024-03-12')).to be(true)
    end

    it 'accepts whole-line date shapes', :aggregate_failures do
      expect(described_class.date_shaped?('2024-03-12')).to be(true)
      expect(described_class.date_shaped?('2024-03-12T12:00:00Z')).to be(true)
      expect(described_class.date_shaped?('12/03/2024')).to be(true)
      expect(described_class.date_shaped?('12 March 2024')).to be(true)
      expect(described_class.date_shaped?('March 12, 2024')).to be(true)
    end

    it 'accepts a date with a type-chip suffix' do
      expect(described_class.date_shaped?('12 March 2024 - News article')).to be(true)
    end

    it 'normalizes unicode space before matching' do
      expect(described_class.date_shaped?("12\u00A0March\u00A02024")).to be(true)
    end

    it 'rejects teasers and space-padded junk', :aggregate_failures do
      expect(described_class.date_shaped?('On 12 March 2024 the company ordered vessels')).to be(false)
      expect(described_class.date_shaped?("a#{' ' * 10_000}")).to be(false)
      expect(described_class.date_shaped?("a - #{'  ' * 5_000}")).to be(false)
    end

    it 'accepts a Nokia-shaped pipe date with spaced comma and clock zone' do
      expect(described_class.date_shaped?('August 06 , 2026 | 13:00 PM Europe/Amsterdam')).to be(true)
    end

    it 'rejects a clock plus teaser after a date separator', :aggregate_failures do
      expect(described_class.date_shaped?('12 March 2024 - 10:00 Team announces a new reactor design'))
        .to be(false)
      expect(described_class.date_shaped?('12 March 2024 | 10:00 Team announces a new reactor design'))
        .to be(false)
    end

    it 'accepts a Telenor-shaped leading type-chip with juli' do
      expect(described_class.date_shaped?('Press release • 16 juli, 2026')).to be(true)
    end
  end

  describe '.date_core Nokia/Telenor fragments' do
    it 'keeps the calendar day from a pipe clock line' do
      expect(described_class.date_core('August 06 , 2026 | 13:00 PM Europe/Amsterdam'))
        .to match(/August 06\s*,?\s*2026/)
    end
  end

  describe '.keep?' do
    it 'drops a Telenor-shaped type-chip date line' do
      expect(described_class.keep?('Press release • 16 juli, 2026', vocabulary:)).to be(false)
    end

    ['Read more', 'Weiterlesen', 'Lire la suite', 'Find out more', 'Meer informatie', 'Más información'].each do |line|
      it "drops the read-more line #{line.inspect}" do
        expect(described_class.keep?(line, vocabulary:)).to be(false)
      end
    end

    it 'keeps a longer read-more sentence' do
      expect(described_class.keep?('Read more about the trial', vocabulary:)).to be(true)
    end

    it 'keeps a teaser that follows a clock, not the whole line as date chrome', :aggregate_failures do
      expect(described_class.keep?('12 March 2024 - 10:00 Team announces a new reactor design',
                                   vocabulary:)).to be(true)
      expect(described_class.keep?('12 March 2024 | 10:00 Team announces a new reactor design',
                                   vocabulary:)).to be(true)
    end

    it 'still drops a Nokia-shaped pipe clock line as description chrome' do
      expect(described_class.keep?('August 06 , 2026 | 13:00 PM Europe/Amsterdam', vocabulary:)).to be(false)
    end

    it 'drops the Japanese type chips 独自 and 写真 on a Japanese or unlabeled page, not on a Chinese one',
       :aggregate_failures do
      %w[独自 写真].product([nil, :ja, :en]).each do |chip, lang|
        expect(described_class.keep?(chip, vocabulary: Html2rss::Vocabulary[lang])).to be(false), "#{chip} #{lang}"
      end
      %w[独自 写真].each { expect(described_class.keep?(_1, vocabulary: Html2rss::Vocabulary[:zh])).to be(true), _1 }
      expect(described_class.keep?('速報', vocabulary: Html2rss::Vocabulary[:zh])).to be(false)
    end

    it 'peels a 独自 or 写真 chip beside a date on every page, in both orders and with every separator',
       :aggregate_failures do
      %w[独自 写真].product([' - ', ' | ', ' • ']).flat_map { |w, sep| ["2024-03-12#{sep}#{w}", "#{w}#{sep}2024-03-12"] }
               .each do |line|
        expect([described_class.date_core(line), described_class.date_shaped?(line)]).to eq(['2024-03-12', true]), line
        expect(described_class.keep?(line, vocabulary: Html2rss::Vocabulary[:zh])).to be(false), line
      end
    end

    it 'sets published_at from such a chip on a Chinese page, and leaves it out of the description',
       :aggregate_failures do
      zh = Html2rss::Vocabulary[:zh]
      line = '独自 | 2026-11-10'

      expect(Html2rss::AutoSource::ArticleRules::Date.earliest([], leftover_lines: [line], time_zone: 'UTC'))
        .to eq(DateTime.parse('2026-11-10T00:00:00Z'))
      expect(described_class.from_lines([line, 'Kept dek'], vocabulary: zh)).to eq('Kept dek')
    end
  end

  describe 'card text read as a description' do
    let(:de) { Html2rss::Vocabulary[:de] }
    let(:dek) { 'The team announced a new reactor design that cuts build time in half.' }

    def describe_text(text, scope = vocabulary)
      lines = described_class.lines_from(text)
      described_class.from_lines(lines, vocabulary: scope)
    end

    it 'drops a share row and keeps the dek', :aggregate_failures do
      expect(describe_text("- Teilen auf Facebook\n- Teilen auf Bluesky\nEin Satz, der bleibt.", de))
        .to eq('Ein Satz, der bleibt.')
      expect(describe_text("Share on Facebook\n#{dek}")).to eq(dek)
    end

    it 'drops a call to action and a reading time', :aggregate_failures do
      expect(describe_text("Zur Merkliste hinzufügen\n3 Min\n#{dek}", de)).to eq(dek)
      expect(describe_text("5 Minuten\n4 min.\n#{dek}")).to eq(dek)
    end

    it 'keeps a line that merely starts with a number and Min', :aggregate_failures do
      expect(describe_text('3 Min Delay Hits Trains')).to eq('3 Min Delay Hits Trains')
      expect(described_class.keep?('3 Min', vocabulary:)).to be(false)
    end

    it 'drops a leading photo credit but not a later one', :aggregate_failures do
      expect(describe_text("© Example Org\n#{dek}")).to eq(dek)
      expect(describe_text("Foto: A. Person\n#{dek}")).to eq(dek)
      expect(describe_text("A. Person – example.com\n#{dek}")).to eq(dek)
      later = "Opening dek line here.\nPhoto: A. Person"
      expect(describe_text(later)).to eq(later)
    end

    it 'drops a short leading label before a longer paragraph', :aggregate_failures do
      expect(describe_text("- Announcement\n#{dek}")).to eq(dek)
      expect(describe_text("Category SDK Published\n#{dek}")).to eq(dek)
      expect(describe_text('Category SDK Published')).to eq('Category SDK Published')
    end

    it 'keeps a long headline-like first line before a paragraph' do
      line = 'Neue Studie zum Klimawandel und Folgen'

      expect(describe_text("#{line}\n#{dek}")).to eq("#{line}\n#{dek}")
    end

    describe 'leading credits and labels' do
      let(:limit) { described_class::MAX_LABEL_CHARS }
      let(:paragraph) { 'p' * described_class::MIN_PARAGRAPH_CHARS }

      {
        'a copyright line' => [['© Example Org', 'Short dek.'], 'Short dek.'],
        'a punctuated photo credit' => [['Foto: A. Person.', 'Short dek.'], 'Short dek.'],
        'a dash host credit' => [['A. Person – example.com', 'Short dek.'], 'Short dek.'],
        'a pipe host credit' => [['A. Person | example.com', 'Short dek.'], 'Short dek.'],
        'two stacked credits' => [['© Example Org', 'Foto: A. Person', 'Short dek.'], 'Short dek.'],
        'a dash line that is no host' => [['Name – Plain text', 'Short dek.'], "Name – Plain text\nShort dek."],
        'a copyright mid-line' => [['Example org © 2026', 'Short dek.'], "Example org © 2026\nShort dek."],
        'a credit after prose' => [['Short dek.', '© Example Org', 'Foto: A. Person'],
                                   "Short dek.\n© Example Org\nFoto: A. Person"]
      }.each do |label, (lines, expected)|
        it "reads #{label}" do
          expect(described_class.from_lines(lines, vocabulary:)).to eq(expected)
        end
      end

      it 'drops a credit of exactly the label length' do
        expect(described_class.from_lines(["© #{'x' * (limit - 2)}", 'Short dek.'], vocabulary:)).to eq('Short dek.')
      end

      it 'keeps a credit one character over the label length' do
        long = "© #{'x' * (limit - 1)}"

        expect(described_class.from_lines([long, 'Short dek.'], vocabulary:)).to eq("#{long}\nShort dek.")
      end

      it 'drops an unpunctuated label before a paragraph of the minimum length' do
        expect(described_class.from_lines(['Label', paragraph], vocabulary:)).to eq(paragraph)
      end

      it 'keeps a label before a paragraph one character short' do
        expect(described_class.from_lines(['Label', paragraph.chop], vocabulary:)).to eq("Label\n#{paragraph.chop}")
      end

      it 'keeps a punctuated first line before a paragraph' do
        expect(described_class.from_lines(['Label.', paragraph], vocabulary:)).to eq("Label.\n#{paragraph}")
      end

      it 'joins list fragments of exactly the fragment length' do
        items = [('a' * described_class::MAX_FRAGMENT_CHARS), ('b' * described_class::MAX_FRAGMENT_CHARS)]

        expect(described_class.lines_from(items.map { |item| "- #{item}" }.join("\n"))).to eq([items.join(', ')])
      end

      it 'keeps list items one character over the fragment length as a list' do
        size = described_class::MAX_FRAGMENT_CHARS + 1
        items = ["- #{'a' * size}", "- #{'b' * size}"]

        expect(described_class.lines_from(items.join("\n"))).to eq(items)
      end
    end

    it 'reads a byline as widget chrome and nil text as no lines', :aggregate_failures do
      expect(described_class.keep?('By Anna Beispiel', vocabulary:)).to be(false)
      expect(described_class.keep?('By the end of the year', vocabulary:)).to be(true)
      expect(described_class.lines_from(nil)).to eq([])
    end

    it 'drops the page title echo' do
      expect(described_class.from_lines(['Page Title', 'Short dek.'], vocabulary:, title: 'page title'))
        .to eq('Short dek.')
    end

    it 'reads labels with the classifier it is given', :aggregate_failures do
      classifier = instance_double(Html2rss::AutoSource::LinkDestination::TextClassifier,
                                   read_more?: true, utility_chrome?: false)

      expect(described_class.from_lines(['Anything here', 'Short dek.'], vocabulary:))
        .to eq("Anything here\nShort dek.")
      expect(described_class.from_lines(['Anything here'], vocabulary:, classifier:)).to be_nil
    end

    it 'joins list fragments into prose' do
      expect(describe_text("#{dek}\n- Solar\n- Wind\n- Hydro")).to eq("#{dek}\nSolar, Wind, Hydro")
    end

    it 'keeps a list of sentences as a list' do
      text = "- Trains run late today.\n- Buses replace the line."
      expect(describe_text(text)).to eq(text)
    end

    it 'keeps a mixed list as a list' do
      text = "- Solar\n- Buses replace the line."
      expect(describe_text(text)).to eq(text)
    end

    it 'reads nil and blank text as no description', :aggregate_failures do
      expect(described_class.lines_from("  \n\n \u00A0 \nkept")).to eq(%w[kept])
      expect(described_class.from_lines(nil, vocabulary:)).to be_nil
    end

    it 'keeps separate prose lines separate', :aggregate_failures do
      expect(described_class.lines_from("Alpha beta\nGamma delta")).to eq(['Alpha beta', 'Gamma delta'])
      expect(describe_text("#{dek}\nSecond fragment\nThird fragment")).to eq("#{dek}\nSecond fragment\nThird fragment")
    end
  end
end
