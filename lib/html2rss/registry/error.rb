# frozen_string_literal: true

module Html2rss
  module Registry
    # Base error for registry bundle operations.
    class Error < Html2rss::Error; end

    # Raised when manifest parsing or emission fails.
    class ManifestError < Error; end

    # Raised when signature or digest verification fails.
    class VerificationError < Error; end

    # Raised when tarball extraction violates safety limits.
    class ArchiveError < Error; end

    # Raised when a bundled config fails schema validation.
    class InvalidConfig < Error; end
  end
end
