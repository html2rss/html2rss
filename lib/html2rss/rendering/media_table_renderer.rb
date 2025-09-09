# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Renders a collapsible table of all available media resources.
    #
    # Creates an HTML <details><summary> section with a table listing
    # all enclosures and fallback images found for an article.
    #
    # @example Basic usage
    #   renderer = MediaTableRenderer.new(
    #     enclosures: [enclosure1, enclosure2],
    #     image: "https://example.com/image.jpg"
    #   )
    #   html = renderer.to_html
    #
    class MediaTableRenderer
      TABLE_HTML = <<~HTML.strip.freeze
        <table>
          <thead>
            <tr>
              <th>Type</th>
              <th>URL</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            %<rows>s
          </tbody>
        </table>
      HTML

      TYPE_MAPPINGS = {
        %r{^image/} => { icon: '🖼️', label: 'Image', action_text: 'View' },
        %r{^video/} => { icon: '🎥', label: 'Video', action_text: 'Play' },
        %r{^audio/} => { icon: '🎵', label: 'Audio', action_text: 'Play' },
        'application/pdf' => { icon: '📄', label: 'PDF Document', action_text: 'Open' }
      }.freeze

      # @param enclosures [Array<Html2rss::RssBuilder::Enclosure>, nil] Media enclosures
      # @param image [String, Addressable::URI, nil] Fallback image URL
      def initialize(enclosures:, image:)
        @enclosures = Array(enclosures)
        @image = image
      end

      # Generates the complete media table HTML.
      #
      # @return [String, nil] The complete media table or nil if no media available
      def to_html
        return nil unless media?

        <<~HTML.strip
          <details>
            <summary>Available resources</summary>
            #{format(TABLE_HTML, rows: table_rows)}
          </details>
        HTML
      end

      private

      def media?
        @enclosures.any? || @image
      end

      def table_rows
        rows = []

        # Add enclosure rows
        rows.concat(@enclosures.map { |enclosure| enclosure_row(enclosure) })

        # Add fallback image row if present and not already covered by enclosures
        rows << image_row(@image) if @image && !image_enclosure?

        rows.join("\n")
      end

      def enclosure_row(enclosure)
        type_icon = type_icon(enclosure.type)
        type_label = type_label(enclosure.type)

        <<~HTML.strip
          <tr>
            <td>#{type_icon} #{type_label}</td>
            <td><a href="#{escaped_url(enclosure.url)}" target="_blank" rel="nofollow noopener noreferrer">#{escaped_url(enclosure.url)}</a></td>
            <td>#{action_links(enclosure)}</td>
          </tr>
        HTML
      end

      def image_row(url)
        <<~HTML.strip
          <tr>
            <td>🖼️ Image</td>
            <td><a href="#{escaped_url(url)}" target="_blank" rel="nofollow noopener noreferrer">#{escaped_url(url)}</a></td>
            <td>#{action_links_html(url, 'View')}</td>
          </tr>
        HTML
      end

      def type_icon(type)
        mapping = find_type_mapping(type)
        mapping&.dig(:icon) || '📎'
      end

      def type_label(type)
        mapping = find_type_mapping(type)
        mapping&.dig(:label) || 'File'
      end

      def action_links(enclosure)
        mapping = find_type_mapping(enclosure.type)
        if mapping
          action_links_html(enclosure.url, mapping[:action_text])
        else
          download_link(enclosure.url)
        end
      end

      def find_type_mapping(type)
        TYPE_MAPPINGS.find { |pattern, _| pattern.is_a?(Regexp) ? pattern =~ type : pattern == type }&.last
      end

      def action_links_html(url, action_text)
        <<~HTML.strip
          <a href="#{escaped_url(url)}" target="_blank" rel="nofollow noopener noreferrer">#{action_text}</a> |
          #{download_link(url)}
        HTML
      end

      def download_link(url)
        <<~HTML.strip
          <a href="#{escaped_url(url)}" target="_blank" rel="nofollow noopener noreferrer" download>Download</a>
        HTML
      end

      def image_enclosure?
        @enclosures.any? { |enclosure| enclosure.type =~ %r{^image/} }
      end

      def escaped_url(url)
        CGI.escapeHTML(url.to_s)
      end
    end
  end
end
