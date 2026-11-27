# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Reads a streamed HTTPX response body while owning the byte count, so an oversize body aborts
    # the transfer instead of downloading to the transport ceiling. The ceiling starts at
    # {Policy#max_stream_bytes} (the widest allowance) and narrows to the per-type cap
    # ({Policy#max_decompressed_bytes_for}) once {SNIFF_BYTES} are in hand, because the type rule may
    # sniff the body when Content-Type is missing or wrong.
    #
    # With an item +limit+ and a feed body, {ItemLimit} watches the stream too: once enough items are in,
    # the transfer is aborted and the cut body is repaired into well-formed XML ({Streamed#truncated}).
    class BodyReader
      # Bytes buffered before the per-type cap is chosen; the response type sniff reads at most 800.
      SNIFF_BYTES = 1024

      # The transport-neutral outcome of a streamed read.
      Streamed = Data.define(:status, :headers, :uri, :body, :truncated)

      ##
      # @param stream [HTTPX::StreamResponse] a response requested with +stream: true+
      # @param policy [Policy] source of the byte caps
      # @param url [Html2rss::Url] request URL, used to classify the response type
      # @param limit [Integer, nil] items the caller keeps; nil reads a feed to its end
      def initialize(stream, policy:, url:, limit: nil)
        @stream = stream
        @policy = policy
        @url = url
        @chunks = []
        @bytes = 0
        @limit = policy.max_stream_bytes
        @item_limit = limit
        @fed = 0
        @truncated = false
      end

      ##
      # @return [Streamed] status, headers, final URI and the decoded body
      # @raise [ResponseTooLarge] when the body crosses its cap; the rest is never read
      def read
        consume
        raise ResponseTooLarge, "Response exceeded #{@limit} bytes" if @bytes > @limit

        Streamed.new(status: @stream.status, headers: @stream.headers, uri: @stream.uri, body:, truncated: @truncated)
      end

      private

      def consume
        @stream.each do |chunk|
          @chunks << chunk
          @bytes += chunk.bytesize
          narrow_limit
          break if stop?
        end
      rescue HTTPX::HTTPError
        nil # 4xx/5xx still carry the response; the caller classifies the status
      end

      def stop?
        return true if @bytes > @limit

        @truncated = enough_items?
      end

      def narrow_limit
        return if @capped || @bytes < SNIFF_BYTES

        @capped = true
        head = Response.new(body: @chunks.join, headers: @stream.headers.to_h, url: @url)
        @limit = @policy.max_decompressed_bytes_for(head)
        @counter = ItemLimit.new(@item_limit) if @item_limit && head.feed_response?
      end

      def enough_items?
        return false unless @counter

        pending = @chunks[@fed..]
        @fed = @chunks.size
        @counter.reached?(pending.join)
      end

      def body
        joined = @chunks.join
        @truncated ? ItemLimit.repair(joined) : joined
      end
    end
  end
end
