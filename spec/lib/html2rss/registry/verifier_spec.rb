# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::Verifier do
  describe '.verify!' do
    it 'accepts a signed bundle with the pinned public key' do
      with_copied_valid_bundle do |bundle_dir|
        manifest = described_class.verify!(bundle_dir, trust: :signed, public_keys:)
        expect(manifest.registry_id).to eq('test')
      end
    end

    it 'rejects unknown public_key_id for signed trust' do
      with_copied_valid_bundle do |bundle_dir|
        expect do
          described_class.verify!(bundle_dir, trust: :signed, public_keys: {})
        end.to raise_error(Html2rss::Registry::VerificationError, /Unknown public_key_id: test-key/)
      end
    end

    it 'rejects missing manifest signature for signed trust' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        File.delete(File.join(bundle_dir, Html2rss::Registry::Manifest::SIGNATURE_FILE))

        expect do
          described_class.verify!(bundle_dir, trust: :signed, public_keys:)
        end.to raise_error(Html2rss::Registry::VerificationError, /Missing manifest.sig/)
      end
    end

    it 'accepts integrity-only verification without a signature' do
      with_copied_valid_bundle do |bundle_dir|
        File.delete(File.join(bundle_dir, Html2rss::Registry::Manifest::SIGNATURE_FILE))
        manifest = described_class.verify!(bundle_dir, trust: :integrity_only, public_keys:)
        expect(manifest.version).to eq('1.0.0')
      end
    end

    it 'rejects tampered config files' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        config_path = File.join(bundle_dir, 'configs/anthropic.com/news.yml')
        File.write(config_path, "#{File.read(config_path)}\n")

        expect do
          described_class.verify!(bundle_dir, trust: :integrity_only, public_keys:)
        end.to raise_error(Html2rss::Registry::VerificationError, /Digest mismatch/)
      end
    end

    it 'rejects invalid signatures' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        File.write(File.join(bundle_dir, Html2rss::Registry::Manifest::SIGNATURE_FILE), ['bad'].pack('m0'))

        expect do
          described_class.verify!(bundle_dir, trust: :signed, public_keys:)
        end.to raise_error(Html2rss::Registry::VerificationError, /Invalid manifest signature/)
      end
    end

    it 'rejects non-Ed25519 public keys' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        rsa_key = OpenSSL::PKey::RSA.generate(2048)

        expect do
          described_class.verify!(
            bundle_dir,
            trust: :signed,
            public_keys: { RegistryTestSupport::TEST_KEY_ID => rsa_key }
          )
        end.to raise_error(Html2rss::Registry::VerificationError, /Public key must be Ed25519/)
      end
    end
  end
end
