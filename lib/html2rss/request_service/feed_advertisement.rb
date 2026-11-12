# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Proof that a page advertises feed URLs in its head (+link[rel=alternate]+ with an
    # RSS/Atom/RDF type and an +http(s)+ href, see {Html::FeedLink}).
    #
    # Built only from a parsed document ({.from_document}), so a caller cannot mint permission
    # for an arbitrary URL: +new+ and +allocate+ are private, an instance and its +feeds+ are
    # frozen, and +dup+/+clone+ return the instance itself (there is no +with+ copy).
    # Reflection (+send(:new)+, +instance_variable_set+ on an allocated object, +Marshal.load+)
    # still can, as nothing in-process can stop it; {Policy} also rejects an unfrozen proof.
    #
    # {Policy} lets an +:advertised_feed+ follow-up leave the page origin only for a URL listed
    # here. A feed off the page origin is recorded as +https+ (an advertised +http:+ feed is
    # fetched as +https:+ or not at all).
    #
    # +feeds+ maps each advertised feed URL to its link title, in document order.
    class FeedAdvertisement
      private_class_method :new, :allocate

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
      # @return [Html2rss::Url] the page the feeds were read from
      attr_reader :page_url

      # @return [Hash{Html2rss::Url => String, nil}] advertised feed URL => link title, in document order
      attr_reader :feeds

      # @param page_url [Html2rss::Url]
      # @param feeds [Hash{Html2rss::Url => String, nil}] frozen
      def initialize(page_url:, feeds:)
        @page_url = page_url
        @feeds = feeds
        freeze
      end

      ##
      # @param url [Html2rss::Url]
      # @return [Boolean] whether the page advertises +url+
      def advertises?(url) = feeds.key?(url)

      # @return [FeedAdvertisement] itself: a proof is immutable, so no copy is ever minted
      def dup = self

      # The proof stays frozen whatever +freeze:+ asks.
      #
      # @return [FeedAdvertisement] itself
      def clone(**) = self
    end
  end
end
