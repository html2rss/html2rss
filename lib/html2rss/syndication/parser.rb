# frozen_string_literal: true

require 'rss'

module Html2rss
  module Syndication
    ##
    # Parses RSS 2.0, RSS 1.0 (RDF), and Atom documents into AutoSource article hashes, with the media
    # files and image each item declares ({ItemMedia}).
    #
    # An Atom entry's URL is its +rel="alternate"+ link or a link without +rel+; an entry with neither
    # (only +enclosure+, +self+ or other links) has no URL and is skipped like any item without one.
    module Parser
      class << self
        ##
        # @param response [Html2rss::RequestService::Response]
        # @return [Array<Hash{Symbol => Object}>] article hashes (may be empty)
        # @raise [ArgumentError] when the response is not a syndication feed
        def parse_response(response)
          raise ArgumentError, 'response is not a syndication feed' unless response.feed_response?

          parse(response.body, base_url: response.url)
        end

        ##
        # @param body [String] raw RSS/RDF/Atom document
        # @param base_url [String, Html2rss::Url, nil] fallback base for relative item links
        # @return [Array<Hash{Symbol => Object}>]
        def parse(body, base_url: nil)
          items = items_from(RSS::Parser.parse(body.to_s, false))
          media = ItemMedia.for_items(body, count: items.size, url: base_url) { |raw| absolute_url(raw, base_url:) }

          items.zip(media).filter_map { |item, item_media| article_hash(item, item_media, base_url:) }
        rescue RSS::Error => error
          Log.warn({
            event_name: 'syndication.parse_failed',
            error_class: error.class.name,
            message: "Syndication::Parser: failed to parse feed (#{error.class}: #{error.message})"
          }.to_json)
          []
        end

        private

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
            absolute_url(item.link, base_url:), media,
            id: item.guid&.content, title: item.title, description: item.description,
            published_at: item.pubDate, author: item.author, categories: item.categories.map(&:content)
          )
        end

        def rdf_item_hash(item, media, base_url:)
          article(
            absolute_url(item.link, base_url:), media,
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
        # +media+ adds the item's +enclosures+ and +image+.
        def article(url, media, id:, title:, description:, published_at:, author:, categories:) # rubocop:disable Metrics/ParameterLists -- the article shape
          return unless url

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

        def atom_text(*nodes) = nodes.find { |node| node }&.content

        def atom_link(entry, base_url:)
          links = entry.links
          link = links.find { |node| node.rel.nil? || node.rel == 'alternate' }
          absolute_url(link&.href, base_url:)
        end

        def atom_author(entry)
          author = entry.author
          return unless author

          present(author.name&.content) || present(author.email&.content)
        end

        def absolute_url(raw, base_url:)
          value = present(raw)
          return unless value

          if base_url
            Url.from_relative(value, base_url)
          else
            Url.from_absolute(value)
          end
        rescue Url::InvalidUrlError
          nil
        end

        def present(value)
          text = value.to_s.strip
          text unless text.empty?
        end
      end
    end
  end
end
