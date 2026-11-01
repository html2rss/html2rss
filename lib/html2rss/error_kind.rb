# frozen_string_literal: true

module Html2rss
  ErrorKind = Data.define(:name, :retryable)

  ##
  # Closed classification of {Html2rss::Error} failures, so consumers branch on a stable
  # symbol instead of exception class names. Read it through {Html2rss::Error#kind}.
  class ErrorKind
    # Frozen name → instance table. Only transient transport failures are retryable.
    ALL = {
      timeout: true,
      blocked: false,
      connection: true,
      invalid_url: false,
      budget: false,
      other: false
    }.to_h { |name, retryable| [name, new(name:, retryable:)] }.freeze
    private_class_method :new

    ##
    # @param name [Symbol, String] one of +ALL.keys+
    # @return [ErrorKind]
    # @raise [ArgumentError] when the name is not a known kind
    def self.[](name) = ALL.fetch(name.to_sym) { raise ArgumentError, "unknown error kind: #{name.inspect}" }

    ##
    # @return [Boolean] whether repeating the same request may succeed
    def retryable? = retryable

    ##
    # @return [Symbol]
    def to_sym = name

    ##
    # @return [String]
    def to_s = name.to_s
  end
end
