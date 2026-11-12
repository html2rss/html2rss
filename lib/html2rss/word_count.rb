# frozen_string_literal: true

module Html2rss
  ##
  # The one definition of a word for the length rules on text (title floor, short anchor labels, description
  # richness). Structural scoring ({Scoring::ContainerAssessor}, {SST::Index}) keeps its own raw letter/digit
  # run count: it is calibrated on page layout, and counting CJK chunks there moves which container wins.
  #
  # A word is a run of letters and digits. Han, Hiragana and Katakana text carries no spaces, so such a
  # run counts one word per {CJK_CHUNK} characters (+アクメ 会員の登録情報…+ is several words, not one).
  module WordCount
    # A run of letters and digits holding at least one Han, Hiragana or Katakana character.
    CJK = /[\p{Han}\p{Hiragana}\p{Katakana}]/
    # Characters of unspaced CJK text that make up one word.
    CJK_CHUNK = 6

    class << self
      ##
      # @param text [String, nil]
      # @param ceiling [Integer, nil] stops counting once this many words are seen
      # @return [Integer] words in +text+, or at least +ceiling+ when counting stopped there
      def count(text, ceiling: nil)
        total = 0
        text.to_s.scan(/\p{Alnum}+/) do |run|
          total += run.match?(CJK) ? run.length.ceildiv(CJK_CHUNK) : 1
          return total if ceiling && total >= ceiling
        end
        total
      end

      ##
      # @param text [String, nil]
      # @param limit [Integer]
      # @return [Boolean] whether +text+ holds at least +limit+ words
      def at_least?(text, limit) = count(text, ceiling: limit) >= limit
    end
  end
end
