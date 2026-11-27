# frozen_string_literal: true

module Html2rss
  class AutoSource
    module EntryResolution
      Scope = Data.define(:name)

      ##
      # How far entry resolution may move away from the requested page: +:section+ keeps candidates
      # at or below the entry URL's directory, +:site+ allows any same-domain candidate.
      class Scope
        # Frozen name → instance table.
        ALL = %i[section site].to_h { |name| [name, new(name:)] }.freeze
        private_class_method :new

        # Default: a requested section is never swapped for the wider site.
        DEFAULT = ALL.fetch(:section)

        ##
        # @param name [Symbol, String] +section+ or +site+
        # @return [Scope]
        # @raise [InvalidOption] when the name is not a known scope
        def self.[](name)
          ALL.fetch(name.to_sym) { raise InvalidOption, "unknown entry resolution scope: #{name.inspect}" }
        end

        ##
        # @param entry_url [Html2rss::Url] the requested page
        # @param url [Html2rss::Url] a candidate page or feed
        # @return [Boolean] whether +url+ lies at or below the entry's section
        def covers?(entry_url, url)
          return true if name == :site

          "#{url.path}/".start_with?(directory(entry_url.path))
        end

        private

        # +/news/world+ → +/news/world/+, +/inland/index.html+ → +/inland/+, empty → +/+.
        def directory(path)
          return path if path.end_with?('/')

          file = path.rpartition('/').last
          file.include?('.') ? path.delete_suffix(file) : "#{path}/"
        end
      end
    end
  end
end
