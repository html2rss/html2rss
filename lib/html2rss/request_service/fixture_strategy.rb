# frozen_string_literal: true

require 'pathname'

module Html2rss
  class RequestService
    # Strategy that returns fixture content for offline or deterministic testing.
    class FixtureStrategy < Strategy
      DEFAULT_CONTENT_TYPE = 'text/html'

      # @return [Response]
      def execute
        path = resolve_fixture_path
        body = path.read
        content_type = ctx.options.fetch(:content_type, DEFAULT_CONTENT_TYPE)

        Response.new(
          body:,
          headers: { 'content-type' => content_type },
          url: ctx.url
        )
      end

      private

      def resolve_fixture_path
        raw_path = ctx.options[:fixture]
        raise ArgumentError, 'Fixture strategy requires :fixture option' unless raw_path

        path = Pathname.new(raw_path)
        path = Pathname.new(Dir.pwd).join(path) unless path.absolute?

        return path if path.file?

        raise ArgumentError, "Fixture file not found: #{path}"
      end
    end
  end
end
