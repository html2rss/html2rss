# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Html2rss::Registry::Signer do
  describe '.sign!' do
    it 'writes an Ed25519 signature for a manifest' do
      manifest = build_fixture_manifest

      Dir.mktmpdir do |bundle_dir|
        path = described_class.sign!(manifest, key_pem: test_private_key_pem, bundle_dir:)
        expect(File.read(path)).not_to be_empty
      end
    end

    it 'rejects non-Ed25519 signing keys' do
      manifest = build_fixture_manifest
      rsa_pem = OpenSSL::PKey::RSA.generate(2048).to_pem

      expect do
        described_class.sign!(manifest, key_pem: rsa_pem, signature_path: '/tmp/manifest.sig')
      end.to raise_error(ArgumentError, /Ed25519/)
    end
  end
end
