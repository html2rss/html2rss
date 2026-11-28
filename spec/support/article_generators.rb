# frozen_string_literal: true

require 'prop_check'

# Article generators for +:property+ examples: well-formed articles that a feed should carry intact.
module ArticleGenerators
  module_function

  GEN = PropCheck::Generators
  FIELDS = %i[url title description author published_at categories id].freeze
  HOSTS = %w[example.com example.org].freeze

  # @return [PropCheck::Generator] an http(s) URL on a reserved example domain
  def url
    GEN.tuple(TextGenerators.pick(%w[http https]), TextGenerators.pick(HOSTS), TextGenerators.words)
       .map { |scheme, host, path| "#{scheme}://#{host}/#{path.join('/')}" }
  end

  # @return [PropCheck::Generator] a plain title
  def title = TextGenerators.words.map { _1.join(' ') }

  # @return [PropCheck::Generator] a person's name such as "Ada Lovelace"
  def person_name = GEN.tuple(word, word).map { |first, last| "#{first.capitalize} #{last.capitalize}" }

  # @return [PropCheck::Generator] an RSS 2.0 person: +jane@example.com+ or +jane@example.com (Jane Doe)+
  def email_person
    GEN.tuple(word, TextGenerators.pick(HOSTS), GEN.one_of(GEN.constant(nil), person_name))
       .map { |local, host, name| ["#{local}@#{host}", name && "(#{name})"].compact.join(' ') }
  end

  # @return [PropCheck::Generator] a DateTime at second precision, in UTC
  def published_at = GEN.choose(0..2_000_000_000).map { Time.at(_1).utc.to_datetime }

  # @return [PropCheck::Generator] category labels, possibly empty
  def categories = GEN.array(word, max: 4)

  # @return [PropCheck::Generator] a description of plain words or tag soup
  def description = GEN.one_of(TextGenerators.words.map { _1.join(' ') }, TextGenerators.html_soup)

  # @param author [PropCheck::Generator] where the author comes from
  # @return [PropCheck::Generator] an Html2rss::Article with every round-tripped field set
  def article(author: GEN.one_of(person_name, email_person))
    GEN.tuple(url, title, description, author, published_at, categories, word).map do |values|
      Html2rss::Article.new(**FIELDS.zip(values).to_h)
    end
  end

  # @return [PropCheck::Generator] one lowercase-or-digit word
  def word = GEN.alphanumeric_string.where { !_1.empty? }
end
