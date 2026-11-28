# frozen_string_literal: true

require 'benchmark'
require 'prop_check'

# Text generators for +:property+ examples: tag soup, URL-like strings and regexp-like strings.
module TextGenerators
  module_function

  # @param values [Array] candidate values
  # @return [PropCheck::Generator] one of +values+, shrinking toward the first
  def pick(values)
    PropCheck::Generators.one_of(*values.map { |value| PropCheck::Generators.constant(value) })
  end

  ANCHOR = '<a href="/x" onclick="y()">'
  HTML_PIECES = [
    '<p>', '</p>', '<b>', '</b>', '<div onmouseover="x()">', '</div>', '<br>', ANCHOR, '</a>',
    '<img src="/i.png" onerror="z()">', '<script>alert(1)</script>', '<SCRIPT src=//e.example/x.js></SCRIPT>',
    '<style>p{}</style>', '<ul><li>', '</li></ul>', '<table><tr><td>', "\n", "\n\n", ' ', "\t", '&amp;', '&lt;',
    '<', '>', '"', 'word', 'lorem ipsum', '__NEWLINE_PLACEHOLDER__'
  ].freeze

  # @param exclude [Array<String>] pieces to leave out
  # @return [PropCheck::Generator] tag soup built from {HTML_PIECES}, hostile markup included
  def html_soup(exclude: [])
    pieces = HTML_PIECES - exclude
    PropCheck::Generators.array(pick(pieces)).map(&:join)
  end

  # @return [PropCheck::Generator] non-empty lowercase words
  def words
    PropCheck::Generators.array(PropCheck::Generators.alphanumeric_string.where { |word| !word.empty? }, min: 1, max: 6)
  end

  URL_PIECES = [
    'http://', 'https://', 'HTTPS://', 'https:\\\\', 'ftp://', 'mailto:', '//', '/', '\\', '?', '#', '@', ':', ':80',
    ':99999',
    'example.com', 'EXAMPLE.com', 'a.b.example', 'xn--bermedien-p9a.example', "\u00fcbermedien.example",
    "www.\u8a79\u59c6\u65af.example", '[::1]', '[2001:db8::1]', '[bad', '1.2.3.4', '999.1.1.1', 'localhost', '.', '..',
    '%20', '%zz', '%', ' ', '_', '-', 'a', 'b/c', 'q=1', '&', '=', "\n", '<', '"', "\u0000", "\u202e"
  ].freeze

  # @param exclude [Array<String>] pieces to leave out
  # @return [PropCheck::Generator] URL-shaped strings built from {URL_PIECES}
  def url_soup(exclude: [])
    PropCheck::Generators.array(pick(URL_PIECES - exclude)).map(&:join)
  end

  # @return [PropCheck::Generator] strings with bytes that may be invalid UTF-8
  def raw_bytes
    PropCheck::Generators.array(PropCheck::Generators.choose(0..255), max: 24).map do |bytes|
      bytes.pack('C*').force_encoding(Encoding::UTF_8)
    end
  end

  # @param exclude [Array<String>] URL pieces to leave out
  # @return [PropCheck::Generator] URL-shaped or arbitrary-byte strings
  def any_text(exclude: [])
    PropCheck::Generators.one_of(url_soup(exclude:), raw_bytes, PropCheck::Generators.printable_ascii_string)
  end

  # Page text reaches the article rules scrubbed (Response decodes and scrubs), so rule properties draw valid UTF-8.
  # @return [PropCheck::Generator] {any_text} with invalid byte sequences replaced
  def valid_text
    any_text.map(&:scrub)
  end

  REGEXP_PIECES = [
    '(', ')', '(?:', '(?<n>', '(?=', '(?!', '(?i)', '[', ']', '[^', '[[:alpha:]]', '{', '}',
    '{2,3}', '{,2}', '{2,}', '*', '+', '?', '*?', '++', '|', '\\', '\\1', '\\k<n>', '\\p{Alpha}',
    '\\h', '/', '/x/i', '^', '$', '.', '-', 'a', 'b', ' ', "\n", "\u00fc", '#'
  ].freeze
  QUANTIFIERS = ['*', '+', '?', '{2,}', '{1,3}', '*?', '++'].freeze

  # @return [PropCheck::Generator] regexp-like strings, mostly malformed, built from {REGEXP_PIECES}
  def regexp_soup
    PropCheck::Generators.array(pick(REGEXP_PIECES), max: 12).map(&:join)
  end

  # @return [PropCheck::Generator] well-formed patterns whose quantified group contains a quantified atom
  def nested_quantifier_pattern
    quantifier = pick(QUANTIFIERS)
    PropCheck::Generators.tuple(pick(%w[a [ab] . \\d]), quantifier, quantifier)
                         .map { |atom, inner, outer| "(#{atom}#{inner})#{outer}" }
  end

  LINE_PIECES = [
    'November', '25', ',', '2026', '2026-11-27', '12 Nov 2026', '| 20:15 PM', 'Press release • 16 juli, 2026',
    'Body text stays here and runs long enough to be a paragraph.', 'By Anna Beispiel', 'Read more', '3 Min',
    'Photo: Anna', '- item', 'Topic:', 'Press releases', 'x', '', ' '
  ].freeze

  # @return [PropCheck::Generator] lists of short leftover lines, dates, chrome and prose mixed
  def line_soup
    PropCheck::Generators.array(pick(LINE_PIECES), max: 10).map { |lines| lines.map(&:dup) }
  end

  BYLINE_PIECES = [
    'By ', 'by ', 'Von ', 'Anna', ' Beispiel', ' and ', ' und ', ', ', '&', ' van ', ' The ', ' of ', ' ', '.', '!',
    '27 Nov 2026 / ', ' / ', "\u00A0", "\n", 'x'
  ].freeze

  # @return [PropCheck::Generator] byline-shaped strings built from {BYLINE_PIECES}
  def byline_soup
    PropCheck::Generators.array(pick(BYLINE_PIECES), max: 12).map(&:join)
  end

  CATEGORY_POOL = %w[News news NEWS Sport sport Art Tech].freeze

  # @return [PropCheck::Generator] up to five lists of category values drawn from a small mixed-case pool
  def category_lists
    PropCheck::Generators.array(PropCheck::Generators.array(pick(CATEGORY_POOL), max: 4), max: 5)
  end

  ADVERSARIAL_UNITS = [' ', ', ', ' and ', 'und ', '1,', 'a.', '- ', ' / '].freeze

  # Generous wall budget in seconds for one adversarial input; a superlinear regexp takes minutes at 50_000.
  TIME_BUDGET = 5

  # @param prefix [String] text before the repeated unit
  # @param suffix [String] text after it
  # @param length [Integer] total length of the repeated part, in characters
  # @return [Array<String>] one string per {ADVERSARIAL_UNITS} entry, cut to +length+
  def adversarial_texts(prefix: '', suffix: '', length: 50_000)
    ADVERSARIAL_UNITS.map { |unit| "#{prefix}#{(unit * ((length / unit.length) + 1))[0, length]}#{suffix}" }
  end

  # @param texts [Array<String>]
  # @yieldparam text [String]
  # @return [Float] the longest wall time of the block over +texts+
  def slowest_seconds(texts)
    texts.map { |text| Benchmark.realtime { yield text } }.max
  end
end
