# frozen_string_literal: true

module Html2rss
  class Channel
    ##
    # Marshal-friendly channel metadata for {FeedResult}.
    #
    # Eagerly materializes values from a live {Channel} so FeedResult never
    # retains a {RequestService::Response} (and its Nokogiri document).
    Snapshot = Data.define(:title, :url, :description, :language, :ttl, :last_build_date, :image, :author) do
      class << self
        ##
        # @param channel [Html2rss::Channel] live channel backed by a response
        # @return [Html2rss::Channel::Snapshot]
        def from(channel)
          new(
            title: channel.title,
            url: channel.url,
            description: channel.description,
            language: channel.language,
            ttl: channel.ttl,
            last_build_date: channel.last_build_date,
            image: channel.image,
            author: channel.author
          )
        end
      end
    end
  end
end
