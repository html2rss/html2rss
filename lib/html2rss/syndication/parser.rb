# frozen_string_literal: true

require 'rss'

module Html2rss
  module Syndication
    ##
    # Parses RSS 2.0 and Atom documents into AutoSource article hashes.
    module Parser
      module_function

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
        return [] unless feed

        items_from(feed, base_url:).filter_map { |item| article_hash(item, base_url:) }
      rescue RSS::Error => error
        Log.warn("Syndication::Parser: failed to parse feed (#{error.class}: #{error.message})")
        []
      end

      def items_from(feed, base_url:) # rubocop:disable Lint/UnusedMethodArgument -- base reserved for callers
        case feed
        when RSS::Rss then Array(feed.items)
        when RSS::Atom::Feed then Array(feed.entries)
        else []
        end
      end
      module_function :items_from
      private_class_method :items_from

      def article_hash(item, base_url:)
        case item
        when RSS::Rss::Channel::Item then rss_item_hash(item, base_url:)
        when RSS::Atom::Entry, RSS::Atom::Feed::Entry then atom_entry_hash(item, base_url:)
        end
      end
      module_function :article_hash
      private_class_method :article_hash

      def rss_item_hash(item, base_url:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- RSS item mapping
        url = absolute_url(item.link, base_url:)
        return unless url

        {
          id: present(item.guid&.content) || url.to_s,
          title: present(item.title),
          description: present(item.description),
          url:,
          published_at: item.date || item.pubDate,
          author: present(item.author),
          categories: Array(item.categories).filter_map { |cat| present(cat.content) }
        }.compact
      end
      module_function :rss_item_hash
      private_class_method :rss_item_hash

      def atom_entry_hash(entry, base_url:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- Atom entry mapping
        url = atom_link(entry, base_url:)
        return unless url

        {
          id: present(entry.id&.content) || url.to_s,
          title: present(atom_text(entry.title)),
          description: present(atom_text(entry.content) || atom_text(entry.summary)),
          url:,
          published_at: entry.published&.content || entry.updated&.content,
          author: present(atom_author(entry)),
          categories: Array(entry.categories).filter_map { |cat| present(cat.term) }
        }.compact
      end
      module_function :atom_entry_hash
      private_class_method :atom_entry_hash

      def atom_link(entry, base_url:)
        links = Array(entry.links)
        link = links.find { |node| node.rel.nil? || node.rel == 'alternate' } || links.first
        absolute_url(link&.href, base_url:)
      end
      module_function :atom_link
      private_class_method :atom_link

      def atom_text(node)
        return if node.nil?

        node.respond_to?(:content) ? node.content : node.to_s
      end
      module_function :atom_text
      private_class_method :atom_text

      def atom_author(entry)
        author = Array(entry.author).first
        return unless author

        present(author.name&.content) || present(author.email&.content)
      end
      module_function :atom_author
      private_class_method :atom_author

      def absolute_url(raw, base_url:)
        value = present(raw)
        return unless value

        if base_url
          Html2rss::Url.from_relative(value, base_url)
        else
          Html2rss::Url.from_absolute(value)
        end
      rescue ArgumentError
        nil
      end
      module_function :absolute_url
      private_class_method :absolute_url

      def present(value)
        text = value.to_s.strip
        text unless text.empty?
      end
      module_function :present
      private_class_method :present
    end
  end
end
