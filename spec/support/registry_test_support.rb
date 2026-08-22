# frozen_string_literal: true

require 'openssl'
require 'fileutils'

module RegistryTestSupport
  FIXTURE_ROOT = File.expand_path('../fixtures/registry', __dir__)
  VALID_BUNDLE = File.join(FIXTURE_ROOT, 'valid')
  TEST_KEY_ID = 'test-key'
  TEST_PRIVATE_KEY = OpenSSL::PKey.read(File.read(File.join(FIXTURE_ROOT, 'test-key.pem'))).freeze
  TEST_PUBLIC_KEY = OpenSSL::PKey.read(File.read(File.join(FIXTURE_ROOT, 'test-key.pub'))).freeze

  module_function

  def test_private_key = TEST_PRIVATE_KEY
  def test_public_key = TEST_PUBLIC_KEY

  def public_keys
    { TEST_KEY_ID => test_public_key }
  end

  def sign_manifest!(bundle_dir, manifest)
    signature = test_private_key.sign(nil, manifest.canonical_bytes)
    File.write(File.join(bundle_dir, Html2rss::Registry::Manifest::SIGNATURE_FILE), [signature].pack('m0'))
  end

  def write_manifest!(bundle_dir, manifest)
    File.write(File.join(bundle_dir, Html2rss::Registry::Manifest::MANIFEST_FILE), manifest.to_json)
    sign_manifest!(bundle_dir, manifest)
  end

  def build_fixture_manifest(bundle_dir: VALID_BUNDLE, registry_id: 'test', version: '1.0.0')
    relative_paths = Html2rss::Registry::CatalogBuilder.config_paths(bundle_dir)
    file_index = Html2rss::Registry::Manifest.file_index(bundle_dir, relative_paths)
    Html2rss::Registry::Manifest.build(
      file_index:,
      registry_id:,
      version:,
      public_key_id: TEST_KEY_ID
    )
  end

  def build_invalid_bundle!
    dir = File.join(FIXTURE_ROOT, 'invalid-config')
    FileUtils.rm_rf(dir)
    write_invalid_config!(dir)
    write_manifest!(dir, invalid_manifest(dir))
    dir
  end

  def with_invalid_bundle
    dir = build_invalid_bundle!
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end

  def write_invalid_config!(dir)
    config_path = File.join(dir, 'configs/example.com/bad.yml')
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, "channel:\n  url: not-a-url\nselectors:\n  items:\n    selector: li\n")
  end

  def invalid_manifest(dir)
    Html2rss::Registry::Manifest.build(
      file_index: Html2rss::Registry::Manifest.file_index(dir, ['configs/example.com/bad.yml']),
      registry_id: 'invalid',
      version: '1.0.0',
      public_key_id: TEST_KEY_ID
    )
  end
end

RSpec.configure do |config|
  config.include RegistryTestSupport
end
