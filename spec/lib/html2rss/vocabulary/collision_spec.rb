# frozen_string_literal: true

require 'nokogiri'

# rubocop:disable RSpec/SpecFilePathFormat

# The collision gate: an unambiguous label term of one language must not read as chrome in the link text of a
# page in another language, unless the pair is reviewed here. A term that is also an ordinary word of another
# language belongs in that language's `ambiguous` list (so it applies only on its own pages); this spec finds the
# terms nobody flagged. Link texts are the anchors of the corpus pages whose root `lang` is one of the eleven
# vocabulary languages; each term is read exactly as the classifier reads it (`TextClassifier.matcher`).
RSpec.describe Html2rss::Vocabulary do
  # [language of the term, term, language of the page] => why the pair is reviewed and allowed. Every entry must
  # still hit (a stale entry fails), so the list only ever shrinks or is re-reviewed.
  let(:reviewed) do
    english_chrome = 'the page is tagged in another language but carries an English chrome link'
    also_danish = 'the word is also a utility label in Danish, so the Danish page reads it as chrome'
    also_norwegian = 'the word is also a utility label in Norwegian, so the Norwegian page reads it as chrome'
    shared_word = 'the same word is a utility label in English too: an international word, not a language clash'
    {
      [:en, 'about', :de] => english_chrome, [:en, 'about', :ja] => english_chrome,
      [:en, 'contact', :de] => english_chrome, [:en, 'contact', :ja] => english_chrome,
      [:en, 'contact', :ro] => shared_word, [:en, 'share', :id] => english_chrome,
      [:en, 'share', :ro] => english_chrome, [:en, 'share', :tr] => english_chrome,
      [:en, 'share', :da] => english_chrome,
      [:de, 'kontakt', :da] => also_danish, [:pl, 'kontakt', :da] => also_danish,
      [:sv, 'kontakt', :da] => also_danish, [:sv, 'kommentarer', :da] => also_danish,
      [:en, 'share', :no] => english_chrome,
      [:de, 'kontakt', :no] => also_norwegian, [:pl, 'kontakt', :no] => also_norwegian,
      [:sv, 'kontakt', :no] => also_norwegian, [:sv, 'kommentarer', :no] => also_norwegian,
      [:sv, 'om oss', :no] => also_norwegian,
      [:en, 'share', :cs] => english_chrome,
      [:en, 'share', :fi] => english_chrome,
      [:de, 'kontakt', :cs] => shared_word, [:pl, 'kontakt', :cs] => shared_word,
      [:sv, 'kontakt', :cs] => shared_word,
      [:fr, 'contact', :en] => shared_word, [:fr, 'contact', :de] => shared_word,
      [:fr, 'contact', :ja] => shared_word, [:fr, 'contact', :ro] => shared_word,
      [:nl, 'contact', :en] => shared_word, [:nl, 'contact', :de] => shared_word,
      [:nl, 'contact', :ja] => shared_word, [:nl, 'contact', :ro] => shared_word
    }
  end

  # Language code => the anchor texts of its corpus pages.
  let(:link_texts) do
    codes = described_class::LANGUAGES.map { _1.code.to_s }
    pages = Dir[File.expand_path('../../../fixtures/auto_source/corpus/*.html', __dir__)]
    pages.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |path, texts|
      doc = Nokogiri::HTML(File.read(path))
      lang = doc.root&.[]('lang').to_s[/\A[a-z]{2,3}/i]&.downcase
      next unless codes.include?(lang)

      doc.css('a').each { texts[lang] << _1.text.unicode_normalize(:nfc).gsub(/[[:space:]]+/, ' ').strip }
    end
  end

  # The [language, term, page language] triples at which an unambiguous term of a language reads as a label in a
  # link text of a page in another language.
  let(:collisions) do
    matcher = Html2rss::AutoSource::LinkDestination::TextClassifier.method(:matcher)
    readings = Html2rss::AutoSource::LinkDestination::TextClassifier::READINGS
    none = described_class::NONE
    lambda do |languages, texts|
      languages.flat_map do |language|
        readings.flat_map do |reading, concepts|
          concepts.flat_map do |concept|
            terms = language.terms.fetch(concept, none) - language.ambiguous.fetch(concept, none)
            terms.flat_map do |term|
              pattern = matcher.call(reading, [described_class.compile([term])])
              texts.except(language.code.to_s).filter_map do |page, links|
                [language.code, term.to_s.downcase, page.to_sym] if links.any? { _1.match?(pattern) }
              end
            end
          end
        end
      end.uniq
    end
  end

  it 'reads the corpus pages of every vocabulary language' do
    expect(link_texts.keys).to match_array(described_class::LANGUAGES.map { _1.code.to_s })
  end

  it 'finds a term of one language that reads as chrome in the link text of another language', :aggregate_failures do
    stray = described_class::Language.new(code: :xx, terms: { utility: %w[Läs Lees] }.freeze)

    expect(collisions.call([stray], link_texts)).to include([:xx, 'läs', :sv], [:xx, 'lees', :nl])
    expect(collisions.call([stray], link_texts)).not_to include([:xx, 'lees', :sv])
  end

  it 'has no unambiguous term reading as chrome in another language page, except the reviewed pairs',
     :aggregate_failures do
    hits = collisions.call(described_class::SHARED_LANGUAGES, link_texts)

    expect(hits - reviewed.keys).to be_empty, "unreviewed collisions: #{(hits - reviewed.keys).inspect}"
    expect(reviewed.keys - hits).to be_empty, "stale reviewed pairs: #{(reviewed.keys - hits).inspect}"
  end
end

# rubocop:enable RSpec/SpecFilePathFormat
