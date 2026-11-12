# frozen_string_literal: true

require_relative 'auto_source_corpus'
require_relative 'revision_comparison'

##
# Offline stand-in for {Html2rss::RequestSession}: answers follow-up requests from a directory of
# saved responses so auto-source's follow-up tiers (native feed, WordPress API, sitemap, oEmbed)
# are measurable without a network. It implements only the session surface auto-source uses.
#
# The directory holds a +manifest.tsv+ of tab-separated +file+ and absolute +url+ lines (the same
# format as a pages directory; see {RevisionComparison.parse_manifest}); +file+ is relative to the
# directory. A url that is not listed fails exactly as an unreachable host does
# ({Html2rss::RequestService::ConnectionFailed}); nothing here ever opens a socket.
class SavedResponses
  # @param dir [String] directory with +manifest.tsv+ and the saved files
  def initialize(dir)
    @dir = dir
    manifest = RevisionComparison.parse_manifest(File.read(File.join(dir, RevisionComparison::MANIFEST)))
    @files = manifest.to_h { [key(_1.url), _1.file] }
  end

  # @param url [String, Html2rss::Url] follow-up request url
  # @return [Html2rss::RequestService::Response] the saved response
  # @raise [Html2rss::RequestService::ConnectionFailed] when no response is saved for the url
  def follow_up(url:, **)
    file = @files.fetch(key(url)) do
      raise Html2rss::RequestService::ConnectionFailed, "no saved response for #{url}"
    end
    AutoSourceCorpus.response(path: File.join(@dir, file), url: url.to_s)
  end

  private

  def key(url) = Html2rss::Url.from_absolute(url).to_s
end
