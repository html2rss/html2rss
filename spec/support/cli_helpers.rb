# frozen_string_literal: true

require 'stringio'

module CliHelpers
  # Capture CLI output while running inside a VCR cassette.
  #
  # @param args [Array<String>] CLI arguments to execute
  # @param cassette [String] VCR cassette name
  # @return [String] captured STDOUT output
  def capture_cli_output(*args, cassette:)
    stdout = StringIO.new
    original_stdout = $stdout
    $stdout = stdout
    VCR.use_cassette(cassette) { Html2rss::CLI.start(args) }
    stdout.string
  ensure
    $stdout = original_stdout
  end
end
