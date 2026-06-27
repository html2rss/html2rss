# frozen_string_literal: true

require 'zlib'

module Html2rss
  class HtmlExtractor
    ##
    # IdGenerator determines the unique ID for an article container node.
    class IdGenerator
      class << self
        ##
        # @param article_tag [Nokogiri::XML::Element] container node
        # @param heading [Nokogiri::XML::Node, nil] heading node
        # @param url [Html2rss::Url, nil] absolute article URL
        # @param selected_anchor [Nokogiri::XML::Node, nil] anchor element
        # @param fallback_anchorless [Boolean] whether to use fallback hashing
        # @return [String, nil] the generated ID, if any
        def call(article_tag, heading:, url:, selected_anchor:, fallback_anchorless:)
          id_from_dom = parse_id_from_dom(article_tag, url, selected_anchor)
          return id_from_dom if id_from_dom

          heading_text = resolve_heading_text(article_tag, heading, fallback_anchorless)
          if heading_text && !heading_text.strip.empty?
            generate_slug(heading_text)
          elsif fallback_anchorless
            generate_content_hash(article_tag)
          end
        end

        private

        def parse_id_from_dom(article_tag, url, selected_anchor)
          candidates = [article_tag['id'], article_tag.at_css('[id]')&.attr('id')]
          candidates += [url&.path, url&.query] if selected_anchor
          candidates.compact.reject(&:empty?).first
        end

        def resolve_heading_text(article_tag, heading, fallback_anchorless)
          text = heading ? TextExtractor.call(heading) : nil
          if text.nil? || text.strip.empty?
            fallback_text_node_content(article_tag, fallback_anchorless)
          else
            text
          end
        end

        def fallback_text_node_content(article_tag, fallback_anchorless)
          return unless fallback_anchorless

          article_tag.xpath('.//text()').find { |t| !t.text.strip.empty? }&.text&.strip
        end

        def generate_slug(text)
          slug = text.downcase.gsub(/[^a-z0-9]+/, '-')
          slug = slug[1..] if slug.start_with?('-')
          slug = slug[0..-2] if slug.end_with?('-')
          slug unless slug.empty?
        end

        def generate_content_hash(article_tag)
          text = TextExtractor.call(article_tag).to_s.strip
          Zlib.crc32(text).to_s(36) unless text.empty?
        end
      end
    end
  end
end
