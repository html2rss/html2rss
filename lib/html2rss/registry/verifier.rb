# frozen_string_literal: true

require 'digest'
require 'openssl'

module Html2rss
  module Registry
    ##
    # Verifies registry bundle integrity and optional Ed25519 signatures.
    module Verifier
      module_function

      ##
      # @param bundle_dir [String]
      # @param trust [Symbol] +:signed+ or +:integrity_only+
      # @param public_keys [Hash{String => OpenSSL::PKey::PKey}] key id => public key
      # @return [Manifest] verified manifest
      def verify!(bundle_dir, trust:, public_keys: {})
        manifest = load_manifest(bundle_dir)
        verify_signature!(bundle_dir, manifest, trust:, public_keys:)
        verify_files!(bundle_dir, manifest)
        manifest
      end

      ##
      # @param bundle_dir [String]
      # @return [Manifest]
      def load_manifest(bundle_dir)
        path = File.join(bundle_dir, Manifest::MANIFEST_FILE)
        raise VerificationError, "Missing #{Manifest::MANIFEST_FILE}" unless File.file?(path)

        Manifest.parse(File.read(path))
      end

      ##
      # @param bundle_dir [String]
      # @param manifest [Manifest]
      # @param trust [Symbol]
      # @param public_keys [Hash{String => OpenSSL::PKey::PKey}]
      # @return [void]
      def verify_signature!(bundle_dir, manifest, trust:, public_keys:)
        case trust
        when :integrity_only
          nil
        when :signed
          verify_ed25519_signature!(bundle_dir, manifest, public_keys:)
        else
          raise VerificationError, "Unknown trust mode: #{trust.inspect}"
        end
      end

      ##
      # @param bundle_dir [String]
      # @param manifest [Manifest]
      # @param public_keys [Hash{String => OpenSSL::PKey::PKey}]
      # @return [void]
      def verify_ed25519_signature!(bundle_dir, manifest, public_keys:)
        signature_path = File.join(bundle_dir, Manifest::SIGNATURE_FILE)
        raise VerificationError, "Missing #{Manifest::SIGNATURE_FILE}" unless File.file?(signature_path)

        public_key = public_keys.fetch(manifest.public_key_id) do
          raise VerificationError, "Unknown public_key_id: #{manifest.public_key_id}"
        end

        signature = File.read(signature_path).strip.unpack1('m0')
        valid = public_key.verify(nil, signature, manifest.canonical_bytes)
        raise VerificationError, 'Invalid manifest signature' unless valid
      rescue ArgumentError => error
        raise VerificationError, "Invalid signature encoding: #{error.message}"
      end

      ##
      # @param bundle_dir [String]
      # @param manifest [Manifest]
      # @return [void]
      def verify_files!(bundle_dir, manifest)
        manifest.files.each do |relative_path, expected_digest|
          absolute_path = File.join(bundle_dir, relative_path)
          raise VerificationError, "Missing file #{relative_path}" unless File.file?(absolute_path)

          actual_digest = Digest::SHA256.file(absolute_path).hexdigest
          next if actual_digest == expected_digest

          raise VerificationError, "Digest mismatch for #{relative_path}"
        end
      end
    end
  end
end
