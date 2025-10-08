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

      PREFIX_TYPE_MAPPINGS = {
        'image/' => { icon: '🖼️', label: 'Image', action_text: 'View' },
        'video/' => { icon: '🎥', label: 'Video', action_text: 'Play' },
        'audio/' => { icon: '🎵', label: 'Audio', action_text: 'Play' }
      }.freeze

      STRING_TYPE_MAPPINGS = {
        'application/pdf' => { icon: '📄', label: 'PDF Document', action_text: 'Open' }
      }.freeze

      # @param enclosures [Array<Html2rss::RssBuilder::Enclosure>, nil] Media enclosures
      # @param image [String, Html2rss::Url, nil] Fallback image URL
      def initialize(enclosures:, image:)
        @enclosures = Array(enclosures)
        @image = image
        @type_mapping_cache = {}
        @has_image_enclosure = @enclosures.any? { |enclosure| enclosure.type&.start_with?('image/') }
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
        rows = @enclosures.map { |enclosure| enclosure_row(enclosure) }
        rows << image_row(@image) if @image && !@has_image_enclosure
        rows.join("\n")
      end

      def enclosure_row(enclosure)
        mapping = type_mapping_for(enclosure.type)
        escaped = escape_url(enclosure.url)
        type_icon = mapping&.fetch(:icon, nil) || '📎'
        type_label = mapping&.fetch(:label, nil) || 'File'

        <<~HTML.strip
          <tr>
            <td>#{type_icon} #{type_label}</td>
            <td><a href="#{escaped}" target="_blank" rel="nofollow noopener noreferrer">#{escaped}</a></td>
            <td>#{action_links_for(escaped, mapping)}</td>
          </tr>
        HTML
      end

      def image_row(url)
        escaped = escape_url(url)

        <<~HTML.strip
          <tr>
            <td>🖼️ Image</td>
            <td><a href="#{escaped}" target="_blank" rel="nofollow noopener noreferrer">#{escaped}</a></td>
            <td>#{action_links_html(escaped, 'View')}</td>
          </tr>
        HTML
      end

      def action_links_for(escaped_url, mapping)
        action_text = mapping&.fetch(:action_text, nil)
        return download_link(escaped_url) unless action_text

        action_links_html(escaped_url, action_text)
      end

      def action_links_html(escaped_url, action_text)
        <<~HTML.strip
          <a href="#{escaped_url}" target="_blank" rel="nofollow noopener noreferrer">#{action_text}</a> |
          #{download_link(escaped_url)}
        HTML
      end

      def download_link(escaped_url)
        <<~HTML.strip
          <a href="#{escaped_url}" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a>
        HTML
      end

      def type_mapping_for(type)
        return if type.nil?

        return @type_mapping_cache[type] if @type_mapping_cache.key?(type)

        @type_mapping_cache[type] = STRING_TYPE_MAPPINGS[type] || prefix_mapping_for(type)
      end

      def prefix_mapping_for(type)
        PREFIX_TYPE_MAPPINGS.each do |prefix, mapping|
          return mapping if type.start_with?(prefix)
        end

        nil
      end

      def escape_url(url)
        CGI.escapeHTML(url.to_s)
      end
    end
  end
end
