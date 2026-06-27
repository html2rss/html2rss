# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Strategy to read a local HTML file.
    class LocalFileStrategy < Strategy
      ##
      # Executes the local file read.
      #
      # @return [Response] the mock response wrapped around the file contents
      # @raise [ArgumentError] if the local file path is missing
      # @raise [Errno::ENOENT] if the file does not exist
      def execute
        file_path = ctx.request[:local_file_path]
        raise ArgumentError, 'Local file path is required for local_file strategy' unless file_path
        raise Errno::ENOENT, "File not found: #{file_path}" unless File.exist?(file_path)

        body = File.read(file_path)
        Response.new(
          body:,
          headers: { 'content-type' => 'text/html; charset=utf-8' },
          url: ctx.url,
          status: 200
        )
      end
    end
  end
end
