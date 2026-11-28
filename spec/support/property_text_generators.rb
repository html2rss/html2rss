# frozen_string_literal: true

require 'prop_check'

# Text generators for +:property+ examples: tag soup, URL-like strings and regexp-like strings.
module PropertyGenerators
  module_function

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
    PropCheck::Generators.array(PropCheck::Generators.one_of(*pieces.map do |piece|
      PropCheck::Generators.constant(piece)
    end))
                         .map(&:join)
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
    PropCheck::Generators.array(PropCheck::Generators.one_of(*(URL_PIECES - exclude).map do |piece|
      PropCheck::Generators.constant(piece)
    end))
                         .map(&:join)
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

  REGEXP_PIECES = [
    '(', ')', '(?:', '(?<n>', '(?=', '(?!', '(?i)', '[', ']', '[^', '[[:alpha:]]', '{', '}',
    '{2,3}', '{,2}', '{2,}', '*', '+', '?', '*?', '++', '|', '\\', '\\1', '\\k<n>', '\\p{Alpha}',
    '\\h', '/', '/x/i', '^', '$', '.', '-', 'a', 'b', ' ', "\n", "\u00fc", '#'
  ].freeze
  QUANTIFIERS = ['*', '+', '?', '{2,}', '{1,3}', '*?', '++'].freeze

  # @return [PropCheck::Generator] regexp-like strings, mostly malformed, built from {REGEXP_PIECES}
  def regexp_soup
    PropCheck::Generators.array(PropCheck::Generators.one_of(*REGEXP_PIECES.map do |piece|
      PropCheck::Generators.constant(piece)
    end), max: 12)
                         .map(&:join)
  end

  # @return [PropCheck::Generator] well-formed patterns whose quantified group contains a quantified atom
  def nested_quantifier_pattern
    quantifier = PropCheck::Generators.one_of(*QUANTIFIERS.map { |piece| PropCheck::Generators.constant(piece) })
    PropCheck::Generators.tuple(PropCheck::Generators.one_of(*%w[a [ab] . \\d].map do |atom|
      PropCheck::Generators.constant(atom)
    end),
                                quantifier, quantifier).map { |atom, inner, outer| "(#{atom}#{inner})#{outer}" }
  end
end
