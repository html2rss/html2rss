# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'rubygems/package'
require 'stringio'
require 'tmpdir'

RSpec.describe Html2rss::Registry::Archive do
  describe '.pack_dir' do
    it 'packs a directory tree into a gzip tar stream' do # rubocop:disable RSpec/ExampleLength
      Dir.mktmpdir do |source_dir|
        configs_dir = File.join(source_dir, 'configs/example.com')
        FileUtils.mkdir_p(configs_dir)
        File.write(File.join(configs_dir, 'feed.yml'), "channel:\n  url: https://example.com\n")

        tar_io = described_class.pack_dir(source_dir)
        Dir.mktmpdir do |destination|
          described_class.extract!(tar_io, into: destination)
          expect(File.read(File.join(destination, 'configs/example.com/feed.yml'))).to include('example.com')
        end
      end
    end
  end

  describe '.extract!' do
    it 'extracts a gzip tar archive into the destination directory' do
      tar_io = build_fixture_tar_gz
      Dir.mktmpdir do |destination|
        described_class.extract!(tar_io, into: destination)
        expect(File.read(File.join(destination, 'configs/example.com/feed.yml'))).to include('example.com')
      end
    end

    it 'rejects path traversal entries' do
      expect do
        Dir.mktmpdir do |destination|
          described_class.extract!(tar_gz_with_entry('../escape.yml', "bad\n"), into: destination)
        end
      end.to raise_error(Html2rss::Registry::ArchiveError, /Path traversal/)
    end

    it 'rejects symlink entries' do
      expect do
        Dir.mktmpdir do |destination|
          described_class.extract!(tar_gz_with_symlink('configs/link', '/etc/passwd'), into: destination)
        end
      end.to raise_error(Html2rss::Registry::ArchiveError, /Symlink not allowed/)
    end

    it 'rejects hard link entries' do # rubocop:disable RSpec/ExampleLength
      expect do
        Dir.mktmpdir do |destination|
          described_class.extract!(tar_gz_with_header(typeflag: '1', name: 'configs/hardlink', linkname: 'target'),
                                   into: destination)
        end
      end.to raise_error(Html2rss::Registry::ArchiveError, /Hard link not allowed/)
    end

    it 'rejects fifo entries' do
      expect do
        Dir.mktmpdir do |destination|
          described_class.extract!(tar_gz_with_header(typeflag: '6', name: 'configs/pipe'), into: destination)
        end
      end.to raise_error(Html2rss::Registry::ArchiveError, /FIFO not allowed/)
    end
  end

  def tar_gz_with_symlink(name, target)
    tar_data = StringIO.new
    Gem::Package::TarWriter.new(tar_data) { |tar| tar.add_symlink(name, target, 0o777) }
    gzip(StringIO.new(tar_data.string))
  end

  def tar_gz_with_header(typeflag:, name:, linkname: nil)
    header = Gem::Package::TarHeader.new(
      name:,
      mode: 0o644,
      size: 0,
      prefix: '',
      typeflag:,
      linkname: linkname.to_s
    ).to_s
    gzip(StringIO.new(header + ("\0" * 512)))
  end

  def build_fixture_tar_gz
    Dir.mktmpdir do |source_dir|
      configs_dir = File.join(source_dir, 'configs/example.com')
      FileUtils.mkdir_p(configs_dir)
      File.write(File.join(configs_dir, 'feed.yml'), "channel:\n  url: https://example.com\n")
      return described_class.pack_dir(source_dir)
    end
  end

  def tar_gz_with_entry(name, body)
    tar_data = StringIO.new
    Gem::Package::TarWriter.new(tar_data) { |tar| tar.add_file(name, 0o644) { |io| io.write(body) } }
    gzip(StringIO.new(tar_data.string))
  end

  def gzip(tar_io)
    buffer = StringIO.new
    Zlib::GzipWriter.wrap(buffer) { |gz| gz.write(tar_io.string) }
    StringIO.new(buffer.string)
  end
end
