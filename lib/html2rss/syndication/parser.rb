# frozen_string_literal: true

require 'rss'

module Html2rss
  module Syndication
    ##
    # Parses RSS 2.0 and Atom documents into AutoSource article hashes.
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
        # @param body [String] raw RSS/Atom document
        # @param base_url [String, Html2rss::Url, nil] fallback base for relative item links
        # @return [Array<Hash{Symbol => Object}>]
        def parse(body, base_url: nil)
          feed = RSS::Parser.parse(body.to_s, false)

          items_from(feed).filter_map { |item| article_hash(item, base_url:) }
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
          when RSS::Rss then feed.items
          when RSS::Atom::Feed then feed.entries
          else []
          end
        end

        def article_hash(item, base_url:)
          case item
          when RSS::Rss::Channel::Item then rss_item_hash(item, base_url:)
          when RSS::Atom::Feed::Entry then atom_entry_hash(item, base_url:)
          end
        end

        def rss_item_hash(item, base_url:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- RSS item mapping
          url = absolute_url(item.link, base_url:)
          return unless url

          {
            id: present(item.guid&.content) || url.to_s,
            title: present(item.title),
            description: present(item.description),
            url:,
            published_at: item.pubDate,
            author: present(item.author),
            categories: item.categories.filter_map { |cat| present(cat.content) }
          }.compact
        end

        def atom_entry_hash(entry, base_url:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- Atom entry mapping
          url = atom_link(entry, base_url:)
          return unless url

          {
            id: present(entry.id&.content) || url.to_s,
            title: present(entry.title&.content),
            description: present(entry.content&.content || entry.summary&.content),
            url:,
            published_at: entry.published&.content || entry.updated&.content,
            author: atom_author(entry),
            categories: entry.categories.filter_map { |cat| present(cat.term) }
          }.compact
        end

        def atom_link(entry, base_url:)
          links = entry.links
          link = links.find { |node| node.rel.nil? || node.rel == 'alternate' } || links.first
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
            Html2rss::Url.from_relative(value, base_url)
          else
            Html2rss::Url.from_absolute(value)
          end
        rescue Html2rss::Url::InvalidUrlError
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
