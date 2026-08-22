# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::Verifier do
  let(:bundle_dir) { RegistryTestSupport::VALID_BUNDLE }

  before do
    write_manifest!(bundle_dir, build_fixture_manifest)
  end

  describe '.verify!' do
    it 'accepts a signed bundle with the pinned public key' do
      manifest = described_class.verify!(bundle_dir, trust: :signed, public_keys:)
      expect(manifest.registry_id).to eq('test')
    end

    it 'accepts integrity-only verification without a signature' do
      File.delete(File.join(bundle_dir, Html2rss::Registry::Manifest::SIGNATURE_FILE))
      manifest = described_class.verify!(bundle_dir, trust: :integrity_only, public_keys:)
      expect(manifest.version).to eq('1.0.0')
    end

    it 'rejects tampered config files' do
      config_path = File.join(bundle_dir, 'configs/anthropic.com/news.yml')
      File.write(config_path, "#{File.read(config_path)}\n")

      expect do
        described_class.verify!(bundle_dir, trust: :integrity_only, public_keys:)
      end.to raise_error(Html2rss::Registry::VerificationError, /Digest mismatch/)
    end

    it 'rejects invalid signatures' do
      File.write(File.join(bundle_dir, Html2rss::Registry::Manifest::SIGNATURE_FILE), ['bad'].pack('m0'))

      expect do
        described_class.verify!(bundle_dir, trust: :signed, public_keys:)
      end.to raise_error(Html2rss::Registry::VerificationError, /Invalid manifest signature/)
    end
  end
end
