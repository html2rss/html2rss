# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleRules::Byline do
  describe '.author_of' do
    it 'reads a byline as an author name only when it is name-shaped', :aggregate_failures do
      expect(described_class.author_of('Von Anna Beispiel')).to eq('Anna Beispiel')
      expect(described_class.author_of('27 Nov 2026 / by Anna van Beispiel')).to eq('Anna van Beispiel')
      expect(described_class.author_of('By the end of the year')).to be_nil
      expect(described_class.author_of('Tram news / by Anna Beispiel')).to be_nil
      expect(described_class.author_of(nil)).to be_nil
    end

    it 'keeps prose and function-word lines out of bylines', :aggregate_failures do
      ['By Land and Sea', 'By The Associated Press', 'By Order of the King', 'Von Die Zeit',
       'By Anna Maria Beispiel Jones Smith'].each do |line|
        expect(described_class.author_of(line)).to be_nil
      end
    end

    it 'reads a one-word name, a particle name and two full names', :aggregate_failures do
      expect(described_class.author_of('By Beispiel')).to eq('Beispiel')
      expect(described_class.author_of('Von Ursula von der Beispiel')).to eq('Ursula von der Beispiel')
      expect(described_class.author_of('By Anna Beispiel and Bob Muster')).to eq('Anna Beispiel and Bob Muster')
    end

    it 'collapses and trims whitespace before reading a byline', :aggregate_failures do
      expect(described_class.author_of("  By Anna Beispiel \n")).to eq('Anna Beispiel')
      expect(described_class.author_of('By  Anna   Beispiel')).to eq('Anna Beispiel')
      expect(described_class.author_of("By\u00A0Anna\u00A0\u00A0Beispiel")).to eq('Anna Beispiel')
    end

    it 'reads a byline of exactly the label length but not one character more', :aggregate_failures do
      at_limit = "By A#{'a' * (described_class::MAX_CHARS - 4)}"

      expect(at_limit.length).to eq(described_class::MAX_CHARS)
      expect(described_class.author_of(at_limit)).to eq(at_limit.delete_prefix('By '))
      expect(described_class.author_of("#{at_limit}a")).to be_nil
    end

    it 'reads the name from a plain byline' do
      expect(described_class.author_of('By Ada Examplesson')).to eq('Ada Examplesson')
    end

    it 'does not read a byline that ends like a sentence' do
      expect(described_class.author_of('By Anna Beispiel.')).to be_nil
    end

    it 'takes the author of the first byline line', :aggregate_failures do
      lines = ['A headline without author', 'By Anna Beispiel', 'By Bert Muster']

      expect(described_class.first_author(lines)).to eq('Anna Beispiel')
      expect(described_class.first_author(lines.drop(1))).to eq('Anna Beispiel')
      expect(described_class.first_author(lines.first(1))).to be_nil
      expect(described_class.first_author([])).to be_nil
    end
  end

  describe 'properties' do
    it 'reads an author as a short substring of the normalised input', :aggregate_failures, :property do
      forall(TextGenerators.byline_soup) do |line|
        author = described_class.author_of(line)
        normalised = line.gsub(/[[:space:]]+/, ' ').strip
        expect(author.nil? || (author.length <= described_class::MAX_CHARS && normalised.include?(author))).to be(true)
      end
    end

    it 'is total over any text', :property do
      forall(TextGenerators.valid_text) do |text|
        expect { described_class.first_author([text, text]) }.not_to raise_error
      end
    end

    it 'reads the longest regexp inputs and 50_000 character lines in bounded time' do
      texts = TextGenerators.adversarial_texts(prefix: 'By A', length: described_class::MAX_CHARS) +
              TextGenerators.adversarial_texts(prefix: 'By A')
      seconds = TextGenerators.slowest_seconds(texts) { |text| described_class.author_of(text) }
      expect(seconds).to be < TextGenerators::TIME_BUDGET
    end
  end

  describe '.date_head' do
    it 'returns the date head of a dated byline only', :aggregate_failures do
      expect(described_class.date_head("27 Nov 2026  /  by Anna Beispiel\n")).to eq('27 Nov 2026')
      expect(described_class.date_head('by Anna Beispiel')).to be_nil
      expect(described_class.date_head('Tram news / by Anna Beispiel')).to be_nil
    end

    it 'ignores a head that is not date-shaped or a tail that is not a byline', :aggregate_failures do
      expect(described_class.date_head('27 Nov 2026 / The tram depot reopens')).to be_nil
      expect(described_class.date_head('27 Nov 2026 / by Anna Beispiel.')).to be_nil
      expect(described_class.date_head(nil)).to be_nil
    end
  end
end
