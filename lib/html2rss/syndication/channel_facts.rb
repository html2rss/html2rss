# frozen_string_literal: true

require 'rss'

module Html2rss
  module Syndication
    ChannelFacts = Data.define(:author, :categories, :explicit)

    ##
    # What a native feed states about its show or publication, for {Html2rss::Channel}: the author
    # name, the iTunes categories and the explicit flag. A fact the feed does not state stays unknown
    # (+nil+, no categories); nothing is guessed.
    #
    # RSS 2.0: the author is +itunes:author+, else the name part of +managingEditor+
    # (+editor@example.com (Name)+ gives +Name+, a plain name is kept, a bare email address is no name);
    # each +itunes:category+ is its +text+ followed by its nested subcategory texts; +itunes:explicit+
    # +true+, +yes+ or +explicit+ is true, +false+, +no+ or +clean+ false, any other value unstated.
    # Atom: the author is the feed +author+ name. RSS 1.0 (RDF) states none of these.
    #
    # @!attribute [r] author
    #   @return [String, nil] the channel author name
    # @!attribute [r] categories
    #   @return [Array<Array<String>>] each category followed by its subcategories
    # @!attribute [r] explicit
    #   @return [Boolean, nil] whether the feed declares explicit content; nil when unstated
    class ChannelFacts
      # +itunes:explicit+ values, lowercased, to the flag they state.
      EXPLICIT = {
        'true' => true, 'yes' => true, 'explicit' => true,
        'false' => false, 'no' => false, 'clean' => false
      }.freeze
      # A +managingEditor+ written as an email address followed by the name in parentheses.
      NAMED_EMAIL = /\A\s*[^\s@]+@\S+\s+\((.+)\)\s*\z/

      class << self
        ##
        # @param feed [RSS::Rss, RSS::RDF, RSS::Atom::Feed, nil] a document the +rss+ library parsed
        # @return [ChannelFacts, nil] the facts an RSS 2.0 or Atom feed states; nil for any other document
        def from(feed)
          case feed
          when RSS::Rss then from_rss(feed.channel)
          when RSS::Atom::Feed then new(author: feed.author&.name&.content)
          end
        end

        private

        def from_rss(channel)
          new(author: rss_author(channel),
              categories: channel.itunes_categories.map { [_1.text, *_1.itunes_categories.map(&:text)] },
              explicit: EXPLICIT[channel.itunes_explicit.to_s.strip.downcase])
        end

        # Blank and padded values are normalized by {#initialize}.
        def rss_author(channel)
          author = channel.itunes_author.to_s
          return author if author.match?(/\S/)

          editor = channel.managingEditor.to_s
          editor[NAMED_EMAIL, 1] || (editor unless editor.include?('@'))
        end
      end

      ##
      # @param author [String, nil] blank becomes nil
      # @param categories [Array<Array<String, nil>>] a category without a name is dropped, blank
      #   subcategories are skipped
      # @param explicit [Boolean, nil]
      def initialize(author: nil, categories: [], explicit: nil)
        super(author: present(author), categories: categories.filter_map { path(_1) }.freeze, explicit:)
      end

      private

      def path((name, *subcategories))
        return unless (name = present(name))

        [name, *subcategories.filter_map { present(_1) }].freeze
      end

      def present(value)
        text = value.to_s.strip
        text.freeze unless text.empty?
      end
    end
  end
end
