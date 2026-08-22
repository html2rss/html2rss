# frozen_string_literal: true

require 'rubygems/package'
require 'zlib'
require 'fileutils'

module Html2rss
  module Registry
    ##
    # Safely extracts registry bundle tar archives with size and slip limits.
    module Archive
      # Maximum compressed tarball bytes accepted during extraction.
      MAX_TARBALL_BYTES = 52_428_800
      # Maximum number of tar entries accepted during extraction.
      MAX_FILES = 10_000
      # Maximum bytes written for a single extracted file.
      MAX_FILE_BYTES = 1_048_576

      module_function

      ##
      # @param tar_io [IO] tar or gzip-compressed tar stream
      # @param into [String] destination directory
      # @return [String] destination directory
      def extract!(tar_io, into:)
        FileUtils.mkdir_p(into)
        state = { bytes: 0, files: 0 }
        with_tar_reader(tar_io) { |tar| extract_tar!(tar, into:, state:) }
        into
      end

      ##
      # @param tar [Gem::Package::TarReader]
      # @param into [String]
      # @param state [Hash{Symbol => Integer}]
      # @return [void]
      def extract_tar!(tar, into:, state:)
        tar.each { |entry| extract_tar_entry!(entry, into:, state:) }
      end

      ##
      # @param entry [Gem::Package::TarReader::Entry]
      # @param into [String]
      # @param state [Hash{Symbol => Integer}]
      # @return [void]
      def extract_tar_entry!(entry, into:, state:)
        state[:files] += 1
        raise ArchiveError, "Archive exceeds max files (#{MAX_FILES})" if state[:files] > MAX_FILES

        validate_entry_path!(entry.full_name)
        return if entry.directory?

        destination = File.join(into, entry.full_name)
        FileUtils.mkdir_p(File.dirname(destination))
        written = write_entry!(entry, destination)
        state[:bytes] += written
        return unless state[:bytes] > MAX_TARBALL_BYTES

        raise ArchiveError, "Archive exceeds max bytes (#{MAX_TARBALL_BYTES})"
      end

      ##
      # @param io [IO]
      # @yieldparam tar [Gem::Package::TarReader]
      # @return [void]
      def with_tar_reader(io, &)
        io.rewind if io.respond_to?(:rewind)
        reader_io = gzip?(io) ? Zlib::GzipReader.new(io) : io
        Gem::Package::TarReader.new(reader_io, &)
      ensure
        reader_io.close if reader_io.is_a?(Zlib::GzipReader)
      end

      ##
      # @param io [IO]
      # @return [Boolean]
      def gzip?(io)
        io.rewind if io.respond_to?(:rewind)
        magic = io.read(2)
        io.rewind if io.respond_to?(:rewind)
        magic == "\x1F\x8B".b
      end

      ##
      # @param relative_path [String]
      # @return [void]
      def validate_entry_path!(relative_path)
        path = relative_path.delete_prefix('./')
        raise ArchiveError, "Absolute path in archive: #{relative_path}" if path.start_with?('/')
        raise ArchiveError, "Path traversal in archive: #{relative_path}" if path.split('/').include?('..')
      end

      ##
      # @param entry [Gem::Package::TarReader::Entry]
      # @param destination [String]
      # @return [Integer] bytes written
      def write_entry!(entry, destination)
        reject_special_entry!(entry)

        written = 0
        File.open(destination, 'wb') do |file|
          while (chunk = entry.read(16_384))
            written += chunk.bytesize
            enforce_file_limit!(entry, written)
            file.write(chunk)
          end
        end
        written
      end

      ##
      # @param entry [Gem::Package::TarReader::Entry]
      # @return [void]
      def reject_special_entry!(entry)
        raise ArchiveError, "Hard link not allowed: #{entry.full_name}" if entry.header.typeflag == '1'
        raise ArchiveError, "Symlink not allowed: #{entry.full_name}" if entry.header.typeflag == '2'
      end

      ##
      # @param entry [Gem::Package::TarReader::Entry]
      # @param written [Integer]
      # @return [void]
      def enforce_file_limit!(entry, written)
        return unless written > MAX_FILE_BYTES

        raise ArchiveError, "File exceeds max bytes (#{MAX_FILE_BYTES}): #{entry.full_name}"
      end
    end
  end
end
