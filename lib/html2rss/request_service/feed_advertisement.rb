# frozen_string_literal: true

module Html2rss
  class RequestService
    FeedAdvertisement = Data.define(:page_url, :feeds)

    ##
    # Proof that a page advertises feed URLs in its head (+link[rel=alternate]+ with an
    # RSS/Atom/RDF type and an +http(s)+ href, see {Html::FeedLink}).
    #
    # Built only from a parsed document, so a caller cannot mint permission for an arbitrary
    # URL. {Policy} lets an +:advertised_feed+ follow-up leave the page origin only for a URL
    # listed here. A feed off the page origin is recorded as +https+ (an advertised +http:+
    # feed is fetched as +https:+ or not at all).
    #
    # +feeds+ maps each advertised feed URL to its link title, in document order.
    class FeedAdvertisement
      private_class_method :new, :[]

      ##
      # @param doc [Nokogiri::HTML::Document] parsed page
      # @param page_url [String, Html2rss::Url] URL the page was fetched from
      # @return [FeedAdvertisement] the page's advertised feeds (possibly none)
      def self.from_document(doc, page_url:)
        page = Url.from_absolute(page_url)
        feeds = Html::FeedLink.from_document(doc).each_with_object({}) do |link, acc|
          url = feed_url(link.href, page)
          acc[url] ||= link.title if url
        end
        new(page_url: page, feeds: feeds.freeze)
      end

      def self.feed_url(href, page)
        url = Url.from_relative(href, page)
        return unless Url::SUPPORTED_SCHEMES.include?(url.scheme)

        Policy.same_origin?(url, page) ? url : url.with_scheme('https')
      rescue Url::InvalidUrlError
        nil
      end
      private_class_method :feed_url

      ##
      # @param url [Html2rss::Url]
      # @return [Boolean] whether the page advertises +url+
      def advertises?(url) = feeds.key?(url)
    end
  end
end
