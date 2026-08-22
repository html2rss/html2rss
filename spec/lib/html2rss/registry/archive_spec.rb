# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'rubygems/package'
require 'stringio'
require 'tmpdir'

RSpec.describe Html2rss::Registry::Archive do
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
  end

  def build_fixture_tar_gz
    Dir.mktmpdir do |source_dir|
      configs_dir = File.join(source_dir, 'configs/example.com')
      FileUtils.mkdir_p(configs_dir)
      File.write(File.join(configs_dir, 'feed.yml'), "channel:\n  url: https://example.com\n")
      return tar_gz_from_source(source_dir)
    end
  end

  def tar_gz_from_source(source_dir)
    tar_data = StringIO.new
    Gem::Package::TarWriter.new(tar_data) do |tar|
      add_tree_to_tar(tar, source_dir)
    end
    gzip(StringIO.new(tar_data.string))
  end

  def add_tree_to_tar(tar, source_dir)
    Dir.glob(File.join(source_dir, '**', '*'), File::FNM_DOTMATCH).each do |path|
      next if File.directory?(path)

      relative = path.delete_prefix("#{source_dir}/")
      tar.add_file(relative, 0o644) { |io| io.write(File.read(path)) }
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
