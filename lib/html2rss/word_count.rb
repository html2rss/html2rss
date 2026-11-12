# frozen_string_literal: true

module Html2rss
  ##
  # Counts text in two facts. {.count} is the one definition of a word for the length rules on text (title
  # floor, short anchor labels, description richness): a run of letters and digits, where Han, Hiragana
  # and Katakana text, which carries no spaces, counts one word per {CJK_CHUNK} characters
  # (+アクメ 会員の登録情報…+ is several words, not one). {.runs} counts raw letter/digit runs, an
  # unspaced CJK run as one: structural scoring ({Scoring::ContainerAssessor}, {SST::Node#run_count}) is
  # calibrated on it, and counting CJK chunks there moves which container wins.
  module WordCount
    # A run of letters and digits holding at least one Han, Hiragana or Katakana character.
    CJK = /[\p{Han}\p{Hiragana}\p{Katakana}]/
    # Characters of unspaced CJK text that make up one word.
    CJK_CHUNK = 6
    # A run of letters and digits.
    RUN = /\p{Alnum}+/

    class << self
      ##
      # @param text [String, nil]
      # @param ceiling [Integer, nil] stops counting once this many words are seen
      # @return [Integer] words in +text+, or at least +ceiling+ when counting stopped there
      def count(text, ceiling: nil)
        total = 0
        text.to_s.scan(RUN) do |run|
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

      ##
      # @param text [String, nil]
      # @param ceiling [Integer, nil] stops counting once this many runs are seen
      # @return [Integer] letter/digit runs in +text+, or +ceiling+ when counting stopped there
      def runs(text, ceiling: nil)
        total = 0
        text.to_s.scan(RUN) do
          total += 1
          return total if total == ceiling
        end
        total
      end
    end
  end
end
