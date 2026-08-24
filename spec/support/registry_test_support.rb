# frozen_string_literal: true

require 'openssl'
require 'fileutils'
require 'tmpdir'
require 'stringio'
require 'rubygems/package'
require 'zlib'

module RegistryTestSupport
  FIXTURE_ROOT = File.expand_path('../fixtures/registry', __dir__)
  VALID_BUNDLE = File.join(FIXTURE_ROOT, 'valid')
  TEST_KEY_ID = 'test-key'
  TEST_PRIVATE_KEY_PEM = File.read(File.join(FIXTURE_ROOT, 'test-key.pem')).freeze
  TEST_PRIVATE_KEY = OpenSSL::PKey.read(TEST_PRIVATE_KEY_PEM).freeze
  TEST_PUBLIC_KEY = OpenSSL::PKey.read(File.read(File.join(FIXTURE_ROOT, 'test-key.pub'))).freeze

  module_function

  def test_private_key = TEST_PRIVATE_KEY
  def test_public_key = TEST_PUBLIC_KEY
  def test_private_key_pem = TEST_PRIVATE_KEY_PEM

  def public_keys
    { TEST_KEY_ID => test_public_key }
  end

  def sign_manifest!(bundle_dir, manifest)
    Html2rss::Registry::Signer.sign!(manifest, key_pem: test_private_key_pem, bundle_dir:)
  end

  def write_manifest!(bundle_dir, manifest)
    File.write(File.join(bundle_dir, Html2rss::Registry::Manifest::MANIFEST_FILE), manifest.to_json)
    sign_manifest!(bundle_dir, manifest)
  end

  def build_fixture_manifest(bundle_dir: VALID_BUNDLE, registry_id: 'test', version: '1.0.0')
    relative_paths = bundled_config_paths(bundle_dir)
    file_index = Html2rss::Registry::Manifest.file_index(bundle_dir, relative_paths)
    Html2rss::Registry::Manifest.build(
      file_index:,
      registry_id:,
      version:,
      public_key_id: TEST_KEY_ID
    )
  end

  def bundled_config_paths(bundle_dir)
    Dir.glob(File.join(bundle_dir, 'configs', '**', '*.yml')).map do |absolute_path|
      absolute_path.delete_prefix("#{bundle_dir}/")
    end.sort
  end

  def manifest_relative_paths(bundle_dir) = bundled_config_paths(bundle_dir)

  ##
  # Yields a writable tmpdir copy of the valid fixture (never mutate shared fixtures).
  #
  # @yieldparam bundle_dir [String]
  # @return [void]
  def with_copied_valid_bundle
    Dir.mktmpdir('registry-valid-') do |tmpdir|
      FileUtils.cp_r(File.join(VALID_BUNDLE, '.'), tmpdir)
      write_manifest!(tmpdir, build_fixture_manifest(bundle_dir: tmpdir))
      yield tmpdir
    end
  end

  def with_invalid_bundle
    Dir.mktmpdir('registry-invalid-') do |dir|
      write_invalid_config!(dir)
      write_manifest!(dir, invalid_manifest(dir))
      yield dir
    end
  end

  def write_invalid_config!(dir)
    config_path = File.join(dir, 'configs/example.com/bad.yml')
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(
      config_path,
      "registry:\n  id: example.com/bad\nchannel:\n  url: not-a-url\nselectors:\n  items:\n    selector: li\n"
    )
  end

  def invalid_manifest(dir)
    Html2rss::Registry::Manifest.build(
      file_index: Html2rss::Registry::Manifest.file_index(dir, ['configs/example.com/bad.yml']),
      registry_id: 'invalid',
      version: '1.0.0',
      public_key_id: TEST_KEY_ID
    )
  end

  def pack_fixture_tar_gz
    Dir.mktmpdir do |source_dir|
      configs_dir = File.join(source_dir, 'configs/example.com')
      FileUtils.mkdir_p(configs_dir)
      File.write(File.join(configs_dir, 'feed.yml'), "channel:\n  url: https://example.com\n")
      return Html2rss::Registry::Archive.pack_dir(source_dir)
    end
  end

  def tar_gz_with_entry(name, body)
    tar_data = StringIO.new
    Gem::Package::TarWriter.new(tar_data) { |tar| tar.add_file(name, 0o644) { |io| io.write(body) } }
    gzip_tar(StringIO.new(tar_data.string))
  end

  def tar_gz_with_symlink(name, target)
    tar_data = StringIO.new
    Gem::Package::TarWriter.new(tar_data) { |tar| tar.add_symlink(name, target, 0o777) }
    gzip_tar(StringIO.new(tar_data.string))
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
    gzip_tar(StringIO.new(header + ("\0" * 512)))
  end

  def gzip_tar(tar_io)
    buffer = StringIO.new
    Zlib::GzipWriter.wrap(buffer) { |gz| gz.write(tar_io.string) }
    StringIO.new(buffer.string)
  end
end

RSpec.configure do |config|
  config.include RegistryTestSupport
end
