# frozen_string_literal: true

require 'stringio'
require 'rubygems/package'
require 'zlib'
require 'fileutils'
require 'forwardable'

module Html2rss
  module Registry
    ##
    # Safely packs and extracts registry bundle tar archives with size and slip limits.
    module Archive
      # Maximum compressed tarball bytes accepted during download/extraction.
      MAX_DOWNLOAD_BYTES = 52_428_800
      # Maximum decompressed bytes written during extraction.
      MAX_EXTRACT_BYTES = 52_428_800
      # Maximum number of tar entries accepted during extraction.
      MAX_FILES = 10_000
      # Maximum bytes written for a single extracted file.
      MAX_FILE_BYTES = 1_048_576

      class << self
        ##
        # @param source_dir [String] directory tree to pack
        # @param io [IO, nil] destination stream; defaults to a new StringIO
        # @return [IO] gzip-compressed tar stream positioned at start
        def pack_dir(source_dir, io: nil)
          tar_data = StringIO.new
          Gem::Package::TarWriter.new(tar_data) { |tar| pack_tree!(tar, source_dir, source_dir) }
          tar_data.rewind

          buffer = StringIO.new
          Zlib::GzipWriter.wrap(buffer) { |gzip| IO.copy_stream(tar_data, gzip) }
          packed = StringIO.new(buffer.string)
          return packed if io.nil?

          io.write(packed.string)
          io.rewind if io.respond_to?(:rewind)
          io
        end

        ##
        # @param tar_io [IO] tar or gzip-compressed tar stream
        # @param into [String] destination directory
        # @return [String] destination directory
        def extract!(tar_io, into:)
          FileUtils.mkdir_p(into)
          state = { download_bytes: 0, extract_bytes: 0, files: 0 }
          counting_io = CountingIO.new(tar_io, limit: MAX_DOWNLOAD_BYTES, label: 'download')
          with_tar_reader(counting_io) { |tar| extract_tar!(tar, into:, state:) }
          into
        end

        private

        def extract_tar!(tar, into:, state:)
          tar.each { |entry| extract_tar_entry!(entry, into:, state:) }
        end

        def extract_tar_entry!(entry, into:, state:)
          state[:files] += 1
          raise ArchiveError, "Archive exceeds max files (#{MAX_FILES})" if state[:files] > MAX_FILES

          BundleRelativePath.validate_archive_entry!(entry.full_name)
          return if entry.directory?

          destination = File.join(into, BundleRelativePath.normalize(entry.full_name))
          FileUtils.mkdir_p(File.dirname(destination))
          written = write_entry!(entry, destination)
          state[:extract_bytes] += written
          return unless state[:extract_bytes] > MAX_EXTRACT_BYTES

          raise ArchiveError, "Archive exceeds max extract bytes (#{MAX_EXTRACT_BYTES})"
        end

        def with_tar_reader(io, &)
          io.rewind if io.respond_to?(:rewind)
          reader_io = gzip?(io) ? Zlib::GzipReader.new(io) : io
          Gem::Package::TarReader.new(reader_io, &)
        ensure
          reader_io.close if reader_io.is_a?(Zlib::GzipReader)
        end

        def gzip?(io)
          io.rewind if io.respond_to?(:rewind)
          magic = io.read(2)
          io.rewind if io.respond_to?(:rewind)
          magic == "\x1F\x8B".b
        end

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

        def reject_special_entry!(entry)
          case entry.header.typeflag
          when '1' then raise ArchiveError, "Hard link not allowed: #{entry.full_name}"
          when '2' then raise ArchiveError, "Symlink not allowed: #{entry.full_name}"
          when '3' then raise ArchiveError, "Character device not allowed: #{entry.full_name}"
          when '4' then raise ArchiveError, "Block device not allowed: #{entry.full_name}"
          when '6' then raise ArchiveError, "FIFO not allowed: #{entry.full_name}"
          end
        end

        def enforce_file_limit!(entry, written)
          return unless written > MAX_FILE_BYTES

          raise ArchiveError, "File exceeds max bytes (#{MAX_FILE_BYTES}): #{entry.full_name}"
        end

        def pack_tree!(tar, source_dir, root_dir)
          Dir.glob(File.join(source_dir, '**', '*'), File::FNM_DOTMATCH).sort.each do |path|
            relative = path.delete_prefix("#{root_dir}/")
            next if relative.empty?

            if File.directory?(path)
              tar.mkdir(relative, 0o755)
            else
              tar.add_file(relative, 0o644) { |io| io.write(File.read(path)) }
            end
          end
        end
      end

      # IO wrapper enforcing a byte limit while reading archive input.
      class CountingIO
        extend Forwardable

        def_delegators :@io, :pos, :seek, :eof?, :close

        # @param io [IO]
        # @param limit [Integer]
        # @param label [String]
        def initialize(io, limit:, label:)
          @io = io
          @limit = limit
          @label = label
          @bytes = 0
        end

        ##
        # @param length [Integer, nil]
        # @param outbuf [String, nil]
        # @return [String, nil]
        def read(length = nil, outbuf = nil)
          chunk = @io.read(length, outbuf)
          track!(chunk)
          chunk
        end

        ##
        # @return [Integer]
        def rewind
          @bytes = 0
          @io.rewind
        end

        private

        def track!(chunk)
          return if chunk.nil?

          @bytes += chunk.bytesize
          return unless @bytes > @limit

          raise ArchiveError, "Archive exceeds max #{@label} bytes (#{@limit})"
        end
      end
      private_constant :CountingIO
    end
  end
end
