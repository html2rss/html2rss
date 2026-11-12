# frozen_string_literal: true

require 'rss'

module Html2rss
  module Syndication
    ##
    # Parses RSS 2.0, RSS 1.0 (RDF), and Atom documents into a {Feed}: AutoSource article hashes, with
    # the media files and image each item declares ({ItemMedia}), and what the feed states about its
    # channel ({ChannelFacts}), read from the same parse.
    #
    # An item's URL is its link (an Atom entry's +rel="alternate"+ link or a link without +rel+). A
    # link-less item (a podcast episode on a hosting platform) takes its guid, Atom +id+ or RDF +about+
    # when that is an absolute http(s) URL, else its first audio or video file; an item with none of
    # these has no URL and is skipped. Links and files resolve against the feed URL through
    # {Url.resolve_web}: a +javascript:+, +data:+ or +ftp:+ one counts as absent, so no item URL is one.
    module Parser
      class << self
        ##
        # @param response [Html2rss::RequestService::Response]
        # @return [Feed]
        # @raise [ArgumentError] when the response is not a syndication feed
        def parse_response(response)
          raise ArgumentError, 'response is not a syndication feed' unless response.feed_response?

          parse(response.body, base_url: response.url)
        end

        ##
        # @param body [String] raw RSS/RDF/Atom document
        # @param base_url [String, Html2rss::Url, nil] fallback base for relative item links
        # @return [Feed] no articles and no channel facts when the document fails to parse
        def parse(body, base_url: nil)
          feed = RSS::Parser.parse(body.to_s, false)
          Feed.new(articles: articles_from(feed, body, base_url:), channel: ChannelFacts.from(feed))
        rescue RSS::Error => error
          Log.warn({
            event_name: 'syndication.parse_failed',
            error_class: error.class.name,
            message: "Syndication::Parser: failed to parse feed (#{error.class}: #{error.message})"
          }.to_json)
          Feed::NONE
        end

        private

        def articles_from(feed, body, base_url:)
          items = items_from(feed)
          media = ItemMedia.for_items(body, count: items.size, url: base_url)

          items.zip(media).filter_map { |item, item_media| article_hash(item, item_media, base_url:) }
        end

        def items_from(feed)
          case feed
          when RSS::Rss, RSS::RDF then feed.items
          when RSS::Atom::Feed then feed.entries
          else []
          end
        end

        def article_hash(item, media, base_url:)
          case item
          when RSS::Rss::Channel::Item then rss_item_hash(item, media, base_url:)
          when RSS::RDF::Item then rdf_item_hash(item, media, base_url:)
          when RSS::Atom::Feed::Entry then atom_entry_hash(item, media, base_url:)
          end
        end

        def rss_item_hash(item, media, base_url:)
          article(
            Url.resolve_web(item.link, base_url), media,
            id: item.guid&.content, title: item.title, description: item.description,
            published_at: item.pubDate, author: item.author, categories: item.categories.map(&:content)
          )
        end

        def rdf_item_hash(item, media, base_url:)
          article(
            Url.resolve_web(item.link, base_url), media,
            id: item.about, title: item.title, description: item.description,
            published_at: item.dc_date, author: item.dc_creator, categories: item.dc_subjects.map(&:content)
          )
        end

        def atom_entry_hash(entry, media, base_url:)
          article(
            atom_link(entry, base_url:), media,
            id: entry.id&.content, title: entry.title&.content, description: atom_text(entry.content, entry.summary),
            published_at: atom_text(entry.published, entry.updated),
            author: atom_author(entry), categories: entry.categories.map(&:term)
          )
        end

        ##
        # Single owner of the article hash shape: blank text becomes absent, +id+ falls back to the url,
        # +media+ adds the item's +enclosures+ and +image+. The url is the item's http(s) link, else its id
        # when that is an absolute http(s) URL, whatever +isPermaLink+ says (+false+ only denies a guaranteed
        # permalink, and such a guid is mostly the item's page on the publisher or its host; a relative, +urn:+
        # or +tag:+ id names no page), else its first audio or video file.
        def article(link, media, id:, title:, description:, published_at:, author:, categories:) # rubocop:disable Metrics/ParameterLists -- the article shape
          return unless (url = link || Url.resolve_web(id) || media_url(media))

          {
            id: present(id) || url.to_s,
            title: present(title),
            description: present(description),
            url:, published_at:,
            author: present(author),
            categories: categories.filter_map { |category| present(category) },
            **media
          }.compact
        end

        def media_url(media)
          media.fetch(:enclosures, []).find { |facts| Article::Enclosure.new(**facts).media? }&.fetch(:url)
        end

        def atom_text(*nodes) = nodes.find { |node| node }&.content

        def atom_link(entry, base_url:)
          link = entry.links.find { |node| node.rel.nil? || node.rel == 'alternate' }
          Url.resolve_web(link&.href, base_url)
        end

        def atom_author(entry)
          author = entry.author
          return unless author

          present(author.name&.content) || present(author.email&.content)
        end

        def present(value)
          text = value.to_s.strip
          text unless text.empty?
        end
      end
    end
  end
end
